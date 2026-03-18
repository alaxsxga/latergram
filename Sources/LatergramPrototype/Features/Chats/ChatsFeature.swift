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
    }

    enum Action {
        case onAppear
        case foregroundRefresh
        case friendTapped(Friend)
        case friendsLoaded([Friend])
        case loadFailed(String)
        case path(StackActionOf<ChatDetailFeature>)
    }

    enum CancelID { case load }

    @Dependency(\.friendClient) var friendClient
    @Dependency(\.currentUser) var currentUser

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                guard state.friends.isEmpty else { return .none }
                state.isLoading = true
                return loadFriends()

            case .foregroundRefresh:
                return loadFriends()

            case .friendTapped(let friend):
                state.path.append(ChatDetailFeature.State(friend: friend))
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

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            ChatDetailFeature()
        }
    }

    private func loadFriends() -> Effect<Action> {
        .run { [id = currentUser.id] send in
            do {
                let friends = try await friendClient.fetchFriends(id)
                await send(.friendsLoaded(friends))
            } catch {
                await send(.loadFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
