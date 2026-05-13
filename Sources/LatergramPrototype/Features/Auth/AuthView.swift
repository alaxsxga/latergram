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
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Credentials (登入 / 註冊)

    private var credentialsView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Latergram")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                TextField("Email", text: $store.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

                SecureField("密碼", text: $store.password)
                    .textContentType(store.mode == .login ? .password : .newPassword)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

                if store.mode == .signUp {
                    SecureField("確認密碼", text: $store.passwordConfirmation)
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
                    .foregroundStyle(.red)
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
                    Text(store.mode == .login ? "登入" : "下一步")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color(red: 0.06, green: 0.06, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(store.isSubmitting)

            Button {
                store.send(.modeSwitchTapped)
            } label: {
                Text(store.mode == .login ? "還沒有帳號？註冊" : "已有帳號？登入")
                    .font(.footnote)
                    .foregroundStyle(Color.brand)
            }

            Spacer()

            #if DEBUG
            debugAccountButtons
            #endif
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Awaiting Confirmation

    private var awaitingConfirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.brand)

            Text("請確認 Email")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("驗證信已寄至 \(store.email)\n點擊信中連結後會自動返回此頁")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            Button {
                store.send(.backTapped)
            } label: {
                Text("重新輸入")
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

            Text("設定你的名稱")
                .font(.title2.bold())
                .foregroundStyle(.white)

            TextField("顯示名稱", text: $store.displayName)
                .textContentType(.name)
                .foregroundStyle(.white)
                .padding()
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
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
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.brand)
            .foregroundStyle(Color(red: 0.06, green: 0.06, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(store.isSubmitting)

            Button {
                store.send(.backTapped)
            } label: {
                Text("返回")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }

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
