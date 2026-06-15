#if os(iOS)
import ComposableArchitecture
import SwiftUI

struct AuthView: View {
    @Bindable var store: StoreOf<AuthFeature>

    var body: some View {
        ZStack {
            Color.pageBg.ignoresSafeArea()
            switch store.mode {
            case .login, .signUp:
                credentialsView
            case .awaitingConfirmation:
                awaitingConfirmationView
            case .setName:
                setNameView
            case .forgotPassword:
                forgotPasswordView
            case .forgotPasswordSent:
                forgotPasswordSentView
            case .resetPassword:
                resetPasswordView
            }
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Credentials (登入 / 註冊)

    private var credentialsView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Latergram")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                TextField(LS("auth.email_placeholder"), text: $store.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

                SecureField(LS("auth.password_placeholder"), text: $store.password)
                    .textContentType(store.mode == .login ? .password : .newPassword)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

                if store.mode == .signUp {
                    SecureField(LS("auth.password_confirm_placeholder"), text: $store.passwordConfirmation)
                        .textContentType(.newPassword)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
                }
            }

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(Color.errorRed)
                    .font(.footnote)
            }

            Button {
                if store.mode == .signUp {
                    store.send(.nextTapped)
                } else {
                    store.send(.submitTapped)
                }
            } label: {
                if store.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    L(store.mode == .login ? "auth.login_button" : "auth.next_button")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color.pageBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(credentialsReady ? 1 : 0.45)
            .disabled(store.isSubmitting || !credentialsReady)

            Button {
                store.send(.modeSwitchTapped)
            } label: {
                L(switchPrefixKey)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                + L(switchActionKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }

            if store.mode == .login {
                Button {
                    store.send(.forgotPasswordTapped)
                } label: {
                    L("auth.forgot_password_button")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()

            #if DEBUG
            debugAccountButtons
            #endif
        }
        .padding(.horizontal, 32)
    }

    private var credentialsReady: Bool {
        !store.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.password.isEmpty
    }

    private var switchPrefixKey: LocalizedStringKey {
        store.mode == .login ? "auth.switch_to_signup.prefix" : "auth.switch_to_login.prefix"
    }

    private var switchActionKey: LocalizedStringKey {
        store.mode == .login ? "auth.switch_to_signup.action" : "auth.switch_to_login.action"
    }

    // MARK: - Awaiting Confirmation

    private var awaitingConfirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)

            L("auth.confirm_email_title")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(format: LS("auth.confirm_email_body"), store.email))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(Color.errorRed)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                store.send(.backTapped)
            } label: {
                L("auth.re_enter_button")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Set Name

    private var setNameView: some View {
        VStack(spacing: 24) {
            Spacer()

            L("auth.set_name_title")
                .font(.title2.bold())
                .foregroundStyle(.white)

            TextField(LS("auth.display_name_placeholder"), text: $store.displayName)
                .textContentType(.name)
                .foregroundStyle(.white)
                .padding()
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(Color.errorRed)
                    .font(.footnote)
            }

            Button {
                store.send(.submitTapped)
            } label: {
                if store.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    L("common.done")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color.pageBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(store.isSubmitting)

            Button {
                store.send(.backTapped)
            } label: {
                L("common.back")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Forgot Password (email input)

    private var forgotPasswordView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.rotation")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)

            L("auth.forgot_password_title")
                .font(.title2.bold())
                .foregroundStyle(.white)

            L("auth.forgot_password_body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))

            TextField(LS("auth.email_placeholder"), text: $store.email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textContentType(.emailAddress)
                .foregroundStyle(.white)
                .padding()
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(Color.errorRed)
                    .font(.footnote)
            }

            Button {
                store.send(.sendResetEmailTapped)
            } label: {
                if store.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    L("auth.send_button")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color.pageBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(store.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .disabled(store.isSubmitting || store.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                store.send(.backTapped)
            } label: {
                L("common.back")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Forgot Password Sent (confirmation)

    private var forgotPasswordSentView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)

            L("auth.forgot_password_sent_title")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(String(format: LS("auth.forgot_password_sent_body"), store.email))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Button {
                store.send(.backTapped)
            } label: {
                L("common.back")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Reset Password (new password input)

    private var resetPasswordView: some View {
        VStack(spacing: 24) {
            Spacer()

            L("auth.reset_password_title")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                SecureField(LS("auth.new_password_placeholder"), text: $store.password)
                    .textContentType(.newPassword)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

                SecureField(LS("auth.password_confirm_placeholder"), text: $store.passwordConfirmation)
                    .textContentType(.newPassword)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
            }

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(Color.errorRed)
                    .font(.footnote)
            }

            Button {
                store.send(.submitTapped)
            } label: {
                if store.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    L("common.done")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color.pageBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(store.isSubmitting)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Debug

    #if DEBUG
    private var debugAccountButtons: some View {
        VStack(spacing: 8) {
            Text("快捷帳號").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(debugAccounts, id: \.email) { account in
                    Button(account.label) {
                        store.send(.set(\.email, account.email))
                        store.send(.set(\.password, account.password))
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cardBg)
                    .foregroundStyle(.white.opacity(0.7))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.bottom, 16)
    }

    private struct DebugAccount {
        let label: String
        let email: String
        let password: String
    }

    private let debugAccounts = [
        DebugAccount(label: "Alaxsxga", email: "alaxsxga@gmail.com", password: "eded99"),
        DebugAccount(label: "Yuni", email: "alaxsxga+yuni@gmail.com", password: "yuni99"),
        DebugAccount(label: "Nong", email: "alaxsxga+nong@gmail.com", password: "nong99")
    ]
    #endif
}

// MARK: - Previews

#Preview("Login") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .login)) { AuthFeature() })
}

#Preview("Sign Up") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .signUp)) { AuthFeature() })
}

#Preview("Awaiting Confirmation") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .awaitingConfirmation, email: "hello@example.com")) { AuthFeature() })
}

#Preview("Set Name") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .setName, pendingUserID: UUID())) { AuthFeature() })
}

#Preview("Forgot Password") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .forgotPassword)) { AuthFeature() })
}

#Preview("Forgot Password Sent") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .forgotPasswordSent, email: "hello@example.com")) { AuthFeature() })
}

#Preview("Reset Password") {
    AuthView(store: Store(initialState: AuthFeature.State(mode: .resetPassword)) { AuthFeature() })
}
#endif
