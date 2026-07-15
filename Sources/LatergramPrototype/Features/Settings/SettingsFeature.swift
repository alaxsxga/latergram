import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct SettingsFeature {
    @ObservableState
    struct State: Equatable {
        var me: UserProfile
        var isConfirmingLogout = false
        var isConfirmingDeleteAccount = false
        var isDeletingAccount = false
        @Presents var paywall: PaywallFeature.State?
        @Presents var feedback: FeedbackFeature.State?
        @Presents var thanksAlert: AlertState<Action.ThanksAlert>?
        @Presents var deleteErrorAlert: AlertState<Action.DeleteErrorAlert>?
    }

    enum Action {
        case logoutConfirmTapped
        case logoutCancelled
        case logoutTapped
        case logoutSucceeded
        case deleteAccountConfirmTapped
        case deleteAccountCancelled
        case deleteAccountTapped
        case accountDeletionSucceeded
        case accountDeletionCancelled
        case accountDeletionFailed(String)
        case upgradeButtonTapped
        case feedbackButtonTapped
        case feedback(PresentationAction<FeedbackFeature.Action>)
        case thanksAlert(PresentationAction<ThanksAlert>)
        case deleteErrorAlert(PresentationAction<DeleteErrorAlert>)
        case paywall(PresentationAction<PaywallFeature.Action>)
        case delegate(Delegate)

        enum ThanksAlert: Equatable {}
        enum DeleteErrorAlert: Equatable {}

        @CasePathable
        enum Delegate: Equatable {
            case logoutSucceeded
            case accountDeleted
            case purchaseSucceeded(UserProfile)
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.appleReauthClient) var appleReauthClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient
    @Dependency(\.messagesCacheClient) var messagesCacheClient
    @Dependency(\.sentryClient) var sentryClient

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

            case .deleteAccountConfirmTapped:
                state.isConfirmingDeleteAccount = true
                return .none

            case .deleteAccountCancelled:
                state.isConfirmingDeleteAccount = false
                return .none

            case .deleteAccountTapped:
                state.isConfirmingDeleteAccount = false
                state.isDeletingAccount = true
                sentryClient.addBreadcrumb(category: "auth", message: "account.delete_requested")
                let userID = state.me.id
                return .run { send in
                    do {
                        // 連結了 Apple identity：刪帳號前重新驗證取得 authorizationCode，讓 server 撤銷 Apple 授權（5.1.1(v)）。
                        // 看 identities 而非當下 session 的 provider——email+apple 連結帳號用 email 登入時也要送 code。
                        var appleAuthorizationCode: String?
                        if await authClient.hasAppleIdentity() {
                            appleAuthorizationCode = try await appleReauthClient.authorizationCode()
                        }
                        try await authClient.deleteAccount(appleAuthorizationCode)
                        // 帳號已刪 → 沿用 logout 的 clean slate 清理（CLAUDE.md #1）
                        friendsCacheClient.clear(userID)
                        messagesCacheClient.clear(userID)
                        await send(.accountDeletionSucceeded)
                    } catch is CancellationError {
                        // 使用者滑掉 Apple 重新驗證面板 → 靜默中止，不刪除也不報錯。
                        await send(.accountDeletionCancelled)
                    } catch {
                        await send(.accountDeletionFailed(error.localizedDescription))
                    }
                }

            case .accountDeletionSucceeded:
                state.isDeletingAccount = false
                return .send(.delegate(.accountDeleted))

            case .accountDeletionCancelled:
                state.isDeletingAccount = false
                sentryClient.addBreadcrumb(category: "auth", message: "account.delete_cancelled")
                return .none

            case .accountDeletionFailed(let message):
                state.isDeletingAccount = false
                sentryClient.addBreadcrumb(
                    category: "auth",
                    message: "account.delete_failed",
                    level: .warning,
                    data: ["error": message]
                )
                state.deleteErrorAlert = AlertState {
                    TextState(LS("settings.delete_account_error_title"))
                } actions: {
                    ButtonState(role: .cancel) { TextState(LS("common.ok")) }
                } message: {
                    TextState(LS("settings.delete_account_error_message"))
                }
                return .none

            case .deleteErrorAlert:
                return .none

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
        .ifLet(\.$deleteErrorAlert, action: \.deleteErrorAlert)
    }
}
