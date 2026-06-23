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
        @Presents var feedback: FeedbackFeature.State?
        @Presents var thanksAlert: AlertState<Action.ThanksAlert>?
    }

    enum Action {
        case logoutConfirmTapped
        case logoutCancelled
        case logoutTapped
        case logoutSucceeded
        case upgradeButtonTapped
        case feedbackButtonTapped
        case feedback(PresentationAction<FeedbackFeature.Action>)
        case thanksAlert(PresentationAction<ThanksAlert>)
        case paywall(PresentationAction<PaywallFeature.Action>)
        case delegate(Delegate)

        enum ThanksAlert: Equatable {}

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

            case .feedbackButtonTapped:
                state.feedback = FeedbackFeature.State(me: state.me)
                return .none

            case .feedback(.presented(.delegate(.submitted))):
                state.feedback = nil
                state.thanksAlert = AlertState {
                    TextState(LS("feedback.thanks_title"))
                } actions: {
                    ButtonState(role: .cancel) { TextState(LS("common.ok")) }
                } message: {
                    TextState(LS("feedback.thanks_message"))
                }
                return .none

            case .feedback:
                return .none

            case .thanksAlert:
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
        .ifLet(\.$feedback, action: \.feedback) {
            FeedbackFeature()
        }
        .ifLet(\.$thanksAlert, action: \.thanksAlert)
    }
}
