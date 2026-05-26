import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var me: UserProfile
        var isConfirmingLogout = false
    }

    enum Action {
        case logoutConfirmTapped
        case logoutCancelled
        case logoutTapped
        case logoutSucceeded
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case logoutSucceeded
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient
    @Dependency(\.messagesCacheClient) var messagesCacheClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .logoutConfirmTapped:
                state.isConfirmingLogout = true
                return .none

            case .logoutCancelled:
                state.isConfirmingLogout = false
                return .none

            case .logoutTapped:
                state.isConfirmingLogout = false
                let userID = state.me.id
                return .run { send in
                    friendsCacheClient.clear(userID)
                    messagesCacheClient.clear(userID)
                    try? await authClient.signOut()
                    await send(.logoutSucceeded)
                }

            case .logoutSucceeded:
                return .send(.delegate(.logoutSucceeded))

            case .delegate:
                return .none
            }
        }
    }
}
