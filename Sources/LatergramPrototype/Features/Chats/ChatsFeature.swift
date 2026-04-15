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
        case friendTapped(Friend)
        case friendsLoaded([Friend])
        case loadFailed(String)
        case messageLimitUpdated(Int)
        case latestMessagesUpdated([UUID: DelayedMessage])
        case path(StackActionOf<ChatDetailFeature>)
    }

    enum CancelID { case load }

    @Dependency(\.friendClient) var friendClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                guard state.friends.isEmpty else { return .none }
                state.isLoading = true
                return loadFriends(userID: state.currentUserID)

            case .foregroundRefresh:
                return loadFriends(userID: state.currentUserID)

            case .friendTapped(let friend):
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

            case .messageLimitUpdated(let limit):
                for id in state.path.ids {
                    state.path[id: id]?.userMessageLimit = limit
                }
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
