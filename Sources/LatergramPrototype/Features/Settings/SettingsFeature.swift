import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var me: UserProfile
        var isConfirmingLogout = false
        @Presents var paywall: PaywallFeature.State?
    }

    enum Action {
        case logoutConfirmTapped
        case logoutCancelled
        case logoutTapped
        case logoutSucceeded
        case upgradeButtonTapped
        case paywall(PresentationAction<PaywallFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case logoutSucceeded
            case purchaseSucceeded(UserProfile)
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

            case .upgradeButtonTapped:
                state.paywall = PaywallFeature.State()
                return .none

            case .paywall(.presented(.delegate(.purchaseSucceeded(let profile)))):
                state.me = profile
                state.paywall = nil
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .paywall:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$paywall, action: \.paywall) {
            PaywallFeature()
        }
    }
}
