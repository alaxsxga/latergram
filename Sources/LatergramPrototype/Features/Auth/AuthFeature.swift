import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct AuthFeature {
    enum Mode: Equatable { case login, signUp, awaitingConfirmation, setName, forgotPassword, forgotPasswordSent, resetPassword }

    @ObservableState
    struct State: Equatable {
        var mode: Mode = .login
        var email = ""
        var password = ""
        var passwordConfirmation = ""
        var displayName = ""
        var pendingUserID: UUID?
        var isSubmitting = false
        var errorMessage: String?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case modeSwitchTapped
        case nextTapped
        case submitTapped
        case backTapped
        case forgotPasswordTapped
        case sendResetEmailTapped
        case passwordResetEmailSent
        case passwordResetLinkOpened
        case accountCreated(UUID)
        case emailConfirmed(UUID)
        case succeeded(UserProfile)
        case failed(String)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .binding:
                return .none

            case .modeSwitchTapped:
                state.mode = state.mode == .login ? .signUp : .login
                state.errorMessage = nil
                state.passwordConfirmation = ""
                state.displayName = ""
                return .none

            case .nextTapped:
                let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
                let password = state.password
                guard !email.isEmpty, !password.isEmpty else {
                    state.errorMessage = LS("auth.error.email_password_required")
                    return .none
                }
                guard password.count >= 6 else {
                    state.errorMessage = LS("auth.error.password_too_short")
                    return .none
                }
                guard password == state.passwordConfirmation else {
                    state.errorMessage = LS("auth.error.password_mismatch")
                    return .none
                }
                sentryClient.addBreadcrumb(category: "auth", message: "auth.sign_up_tapped")
                state.errorMessage = nil
                state.isSubmitting = true
                return .run { [sentryClient] send in
                    do {
                        let userID = try await authClient.createAccount(email, password)
                        await send(.accountCreated(userID))
                    } catch {
                        SentryBootstrap.captureBackend(error, op: "auth.create_account")
                        await send(.failed(localizedAuthErrorMessage(error)))
                    }
                }

            case .forgotPasswordTapped:
                state.mode = .forgotPassword
                state.errorMessage = nil
                return .none

            case .sendResetEmailTapped:
                let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !email.isEmpty else {
                    state.errorMessage = LS("auth.error.email_required")
                    return .none
                }
                sentryClient.addBreadcrumb(category: "auth", message: "auth.send_reset_email_tapped")
                state.isSubmitting = true
                state.errorMessage = nil
                return .run { send in
                    do {
                        try await authClient.sendPasswordReset(email)
                        await send(.passwordResetEmailSent)
                    } catch {
                        SentryBootstrap.captureBackend(error, op: "auth.send_password_reset")
                        await send(.failed(localizedAuthErrorMessage(error)))
                    }
                }

            case .passwordResetEmailSent:
                state.isSubmitting = false
                state.mode = .forgotPasswordSent
                return .none

            case .passwordResetLinkOpened:
                sentryClient.addBreadcrumb(category: "auth", message: "auth.password_reset_link_opened")
                state.password = ""
                state.passwordConfirmation = ""
                state.errorMessage = nil
                state.mode = .resetPassword
                return .none

            case .backTapped:
                switch state.mode {
                case .setName:
                    state.mode = .signUp
                    state.pendingUserID = nil
                case .forgotPassword, .forgotPasswordSent:
                    state.mode = .login
                default:
                    state.mode = .signUp
                }
                state.password = ""
                state.passwordConfirmation = ""
                state.errorMessage = nil
                state.displayName = ""
                return .none

            case .accountCreated(let userID):
                sentryClient.addBreadcrumb(category: "auth", message: "auth.account_created")
                state.isSubmitting = false
                state.pendingUserID = userID
                state.mode = .awaitingConfirmation
                return .none

            case .emailConfirmed(let userID):
                sentryClient.addBreadcrumb(category: "auth", message: "auth.email_confirmed")
                state.pendingUserID = userID
                state.mode = .setName
                return .none

            case .submitTapped:
                let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
                let password = state.password
                state.isSubmitting = true
                state.errorMessage = nil
                if state.mode == .resetPassword {
                    let newPassword = state.password
                    let confirmation = state.passwordConfirmation
                    guard !newPassword.isEmpty else {
                        state.isSubmitting = false
                        state.errorMessage = LS("auth.error.new_password_required")
                        return .none
                    }
                    guard newPassword.count >= 6 else {
                        state.isSubmitting = false
                        state.errorMessage = LS("auth.error.password_too_short")
                        return .none
                    }
                    guard newPassword == confirmation else {
                        state.isSubmitting = false
                        state.errorMessage = LS("auth.error.password_mismatch")
                        return .none
                    }
                    sentryClient.addBreadcrumb(category: "auth", message: "auth.reset_password_tapped")
                    return .run { send in
                        do {
                            try await authClient.updatePassword(newPassword)
                            let user = await authClient.currentSession() ?? UserProfile(displayName: "")
                            await send(.succeeded(user))
                        } catch {
                            SentryBootstrap.captureBackend(error, op: "auth.update_password")
                            await send(.failed(localizedAuthErrorMessage(error)))
                        }
                    }
                }
                if state.mode == .setName {
                    let displayName = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !displayName.isEmpty else {
                        state.isSubmitting = false
                        state.errorMessage = LS("auth.error.display_name_required")
                        return .none
                    }
                    guard let userID = state.pendingUserID else {
                        state.isSubmitting = false
                        state.errorMessage = LS("auth.error.generic")
                        return .none
                    }
                    sentryClient.addBreadcrumb(category: "auth", message: "auth.set_name_tapped")
                    return .run { [sentryClient] send in
                        do {
                            let user = try await authClient.setDisplayName(userID, displayName)
                            await send(.succeeded(user))
                        } catch {
                            SentryBootstrap.captureBackend(error, op: "auth.set_display_name")
                            await send(.failed(localizedAuthErrorMessage(error)))
                        }
                    }
                }
                sentryClient.addBreadcrumb(category: "auth", message: "auth.sign_in_tapped")
                return .run { [sentryClient] send in
                    do {
                        let user = try await authClient.signIn(email, password)
                        await send(.succeeded(user))
                    } catch {
                        if !isUserInputAuthError(error) {
                            SentryBootstrap.captureBackend(error, op: "auth.sign_in")
                        }
                        await send(.failed(localizedAuthErrorMessage(error)))
                    }
                }

            case .succeeded:
                let flow: String
                switch state.mode {
                case .setName: flow = "sign_up"
                case .resetPassword: flow = "reset_password"
                default: flow = "sign_in"
                }
                sentryClient.addBreadcrumb(
                    category: "auth",
                    message: "auth.succeeded",
                    data: ["flow": flow]
                )
                state.isSubmitting = false
                return .none

            case .failed(let message):
                sentryClient.addBreadcrumb(
                    category: "auth",
                    message: "auth.failed",
                    level: .warning,
                    data: ["flow": authFailureFlow(for: state.mode)]
                )
                state.isSubmitting = false
                state.errorMessage = message
                return .none
            }
        }
    }

    private func authFailureFlow(for mode: Mode) -> String {
        switch mode {
        case .login: return "sign_in"
        case .signUp, .setName, .awaitingConfirmation: return "sign_up"
        case .forgotPassword, .forgotPasswordSent: return "forgot_password"
        case .resetPassword: return "reset_password"
        }
    }
}
