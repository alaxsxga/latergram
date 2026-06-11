import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct AuthFeature {
    enum Mode: Equatable { case login, signUp, awaitingConfirmation, setName }

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
                    state.errorMessage = "請填寫 Email 與密碼"
                    return .none
                }
                guard password == state.passwordConfirmation else {
                    state.errorMessage = "兩次密碼不一致"
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
                        sentryClient.captureBackend(error, op: "auth.create_account")
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .backTapped:
                state.mode = .signUp
                state.password = ""
                state.passwordConfirmation = ""
                state.errorMessage = nil
                state.displayName = ""
                state.pendingUserID = nil
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
                if state.mode == .setName {
                    let displayName = state.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !displayName.isEmpty else {
                        state.isSubmitting = false
                        state.errorMessage = "請填寫顯示名稱"
                        return .none
                    }
                    guard let userID = state.pendingUserID else {
                        state.isSubmitting = false
                        state.errorMessage = "發生錯誤，請重新嘗試"
                        return .none
                    }
                    sentryClient.addBreadcrumb(category: "auth", message: "auth.set_name_tapped")
                    return .run { [sentryClient] send in
                        do {
                            let user = try await authClient.setDisplayName(userID, displayName)
                            await send(.succeeded(user))
                        } catch {
                            sentryClient.captureBackend(error, op: "auth.set_display_name")
                            await send(.failed(error.localizedDescription))
                        }
                    }
                }
                sentryClient.addBreadcrumb(category: "auth", message: "auth.sign_in_tapped")
                return .run { [sentryClient] send in
                    do {
                        let user = try await authClient.signIn(email, password)
                        await send(.succeeded(user))
                    } catch {
                        sentryClient.captureBackend(error, op: "auth.sign_in")
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .succeeded:
                sentryClient.addBreadcrumb(
                    category: "auth",
                    message: "auth.succeeded",
                    data: ["flow": state.mode == .setName ? "sign_up" : "sign_in"]
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
        }
    }
}
