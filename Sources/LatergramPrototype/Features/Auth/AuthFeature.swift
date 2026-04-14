import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct AuthFeature {
    enum Mode: Equatable { case login, signUp, setName }

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
        case succeeded(UserProfile)
        case failed(String)
    }

    @Dependency(\.authClient) var authClient

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
                state.errorMessage = nil
                state.isSubmitting = true
                return .run { send in
                    do {
                        let userID = try await authClient.createAccount(email, password)
                        await send(.accountCreated(userID))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .backTapped:
                state.mode = .signUp
                state.errorMessage = nil
                state.displayName = ""
                state.pendingUserID = nil
                return .none

            case .accountCreated(let userID):
                state.isSubmitting = false
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
                    return .run { send in
                        do {
                            let user = try await authClient.setDisplayName(userID, displayName)
                            await send(.succeeded(user))
                        } catch {
                            await send(.failed(error.localizedDescription))
                        }
                    }
                }
                return .run { send in
                    do {
                        let user = try await authClient.signIn(email, password)
                        await send(.succeeded(user))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .succeeded:
                state.isSubmitting = false
                return .none

            case .failed(let message):
                state.isSubmitting = false
                state.errorMessage = message
                return .none
            }
        }
    }
}
