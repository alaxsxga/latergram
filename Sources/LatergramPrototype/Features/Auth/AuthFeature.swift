import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct AuthFeature {
    enum Mode: Equatable { case login, signUp }

    @ObservableState
    struct State: Equatable {
        var mode: Mode = .login
        var email = ""
        var password = ""
        var passwordConfirmation = ""
        var isSubmitting = false
        var errorMessage: String?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case modeSwitchTapped
        case submitTapped
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
                return .none

            case .submitTapped:
                let email = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
                let password = state.password
                guard !email.isEmpty, !password.isEmpty else {
                    state.errorMessage = "請填寫 Email 與密碼"
                    return .none
                }
                if state.mode == .signUp, password != state.passwordConfirmation {
                    state.errorMessage = "兩次密碼不一致"
                    return .none
                }
                state.isSubmitting = true
                state.errorMessage = nil
                let mode = state.mode
                return .run { send in
                    do {
                        let user = try await mode == .login
                            ? authClient.signIn(email, password)
                            : authClient.signUp(email, password)
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
