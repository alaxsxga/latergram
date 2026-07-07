import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct ChatsFeature {
    @ObservableState
    struct State: Equatable {
        var friends: IdentifiedArrayOf<Friend> = []
        var isLoading = false
        var path = StackState<ChatDetailFeature.State>()
        var currentUserID: UUID = UUID()
        var currentUserName: String = ""
        var latestMessages: [UUID: DelayedMessage] = [:]  // friendID → latest message
    }

    enum Action {
        case onAppear
        case foregroundRefresh
        case reset
        case friendTapped(Friend)
        case friendsLoaded([Friend])
        case loadFailed(String)
        case latestMessagesUpdated([UUID: DelayedMessage])
        case path(StackActionOf<ChatDetailFeature>)
    }

    enum CancelID { case load }

    @Dependency(\.friendClient) var friendClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                // Sync from the shared friends cache on every appear — other
                // features (e.g. accepting an invite on the Friends tab) update
                // it while this tab is inactive.
                let cached = friendsCacheClient.load(state.currentUserID)
                if !cached.isEmpty {
                    state.friends = IdentifiedArray(
                        uniqueElements: cached.filter { $0.status == .accepted }
                    )
                }
                guard state.friends.isEmpty else { return .none }
                state.isLoading = true
                return loadFriends(userID: state.currentUserID)

            case .reset:
                state = State()
                return .cancel(id: CancelID.load)

            case .foregroundRefresh:
                let cached = friendsCacheClient.load(state.currentUserID)
                if !cached.isEmpty {
                    state.friends = IdentifiedArray(
                        uniqueElements: cached.filter { $0.status == .accepted }
                    )
                }
                return .none

            case .friendTapped(let friend):
                sentryClient.addBreadcrumb(
                    category: "nav",
                    message: "chat.detail.opened",
                    data: ["friendID": friend.id.uuidString]
                )
                state.path.append(ChatDetailFeature.State(
                    friend: friend,
                    currentUserID: state.currentUserID,
                    senderName: state.currentUserName
                ))
                return .none

            case .friendsLoaded(let friends):
                state.isLoading = false
                state.friends = IdentifiedArray(
                    uniqueElements: friends.filter { $0.status == .accepted }
                )
                return .none

            case .loadFailed:
                state.isLoading = false
                return .none

            case .latestMessagesUpdated(let latest):
                state.latestMessages = latest
                return .none

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            ChatDetailFeature()
        }
    }

    private func loadFriends(userID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let friends = try await friendClient.fetchFriends(userID)
                await send(.friendsLoaded(friends))
            } catch {
                await send(.loadFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
