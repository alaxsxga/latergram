import Auth
import ComposableArchitecture
import Functions
import LatergramCore
import Foundation

@DependencyClient
struct AuthClient: Sendable {
    var signIn: @Sendable (_ email: String, _ password: String) async throws -> UserProfile
    var signInWithApple: @Sendable (_ idToken: String, _ nonce: String) async throws -> AppleSignInResult
    var signUp: @Sendable (_ email: String, _ password: String, _ displayName: String) async throws -> UserProfile
    var createAccount: @Sendable (_ email: String, _ password: String) async throws -> UUID
    var setDisplayName: @Sendable (_ userID: UUID, _ displayName: String) async throws -> UserProfile
    var signOut: @Sendable () async throws -> Void
    var currentSession: @Sendable () async -> UserProfile?
    var handleDeepLink: @Sendable (_ url: URL) async throws -> UUID
    var sendPasswordReset: @Sendable (_ email: String) async throws -> Void
    var updatePassword: @Sendable (_ newPassword: String) async throws -> Void
    var deleteAccount: @Sendable (_ appleAuthorizationCode: String?) async throws -> Void
    /// 帳號是否連結了 Apple identity（連結帳號可能同時有 email + apple）。
    /// 判斷刪帳號前是否需要重新驗證取 code 撤銷授權——必須看 identities 陣列，
    /// 不能只看當下 session 的單數 provider，否則 email session 刪連結帳號會漏送 code → server 擋 400。
    var hasAppleIdentity: @Sendable () async -> Bool = { false }
}

extension AuthClient: DependencyKey {
    static let liveValue = AuthClient(
        signIn: { email, password in
            let session = try await tracedSupabase("auth.sign_in") {
                try await supabase.auth.signIn(email: email, password: password)
            }
            let profile: ProfileRow = try await tracedSupabase("profiles.fetch_self") {
                try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: session.user.id)
                    .single()
                    .execute()
                    .value
            }
            return profile.toUserProfile(id: session.user.id)
        },
        signInWithApple: { idToken, nonce in
            // idToken 走 OpenID Connect：Supabase 依 idToken 對應（或建立）auth.users，
            // 建立時 handle_new_user trigger 會用 email local-part 塞 display_name 當 fallback。
            let session = try await tracedSupabase("auth.sign_in_apple") {
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
            }
            let userID = session.user.id
            let profile: ProfileRow = try await tracedSupabase("profiles.fetch_self") {
                try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userID)
                    .single()
                    .execute()
                    .value
            }
            // 判斷是否還沒有「使用者自訂的名字」：display_name 為空、或仍等於 trigger 用
            // email/轉發信箱 local-part 塞的 fallback。是的話（＝首次註冊、或既有未命名帳號
            // 被連結）就讓上層導到 setName 頁自行輸入，不用 Apple 給的名字預填。既有已命名的
            // 帳號（老用戶、或有名字的 email 帳號被連結）則直接放行。
            let emailLocalPart = session.user.email?.split(separator: "@").first.map(String.init)
            let needsDisplayName = profile.display_name.isEmpty || profile.display_name == emailLocalPart
            return AppleSignInResult(
                profile: profile.toUserProfile(id: userID),
                needsDisplayName: needsDisplayName
            )
        },
        signUp: { email, password, displayName in
            let response = try await tracedSupabase("auth.sign_up") {
                try await supabase.auth.signUp(email: email, password: password)
            }
            try await tracedSupabase("profiles.set_display_name") {
                _ = try await supabase
                    .from("profiles")
                    .update(["display_name": displayName])
                    .eq("id", value: response.user.id)
                    .execute()
            }
            let profile: ProfileRow = try await tracedSupabase("profiles.fetch_self") {
                try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: response.user.id)
                    .single()
                    .execute()
                    .value
            }
            return profile.toUserProfile(id: response.user.id)
        },
        createAccount: { email, password in
            let response = try await tracedSupabase("auth.sign_up") {
                // 註記：不傳 redirectTo。確認信的連結由 email 模板（Confirm signup）自組，
                // 指向 Cloudflare 中間頁並在「fragment」夾帶 token_hash：
                //   https://latergram-verify.alaxsxga-dev.workers.dev/#token_hash={{ .TokenHash }}&type=signup
                // 這樣 token 不會在「點連結」當下被 Supabase verify 消耗掉（避免電腦先點就把
                // 帳號確認掉的跨裝置陷阱），改由手機上的 App 呼叫 verifyOtp 才消耗（見 handleDeepLink）。
                // token 放 fragment 是為了讓中間頁的 host 收不到它（fragment 不送伺服器）。
                try await supabase.auth.signUp(email: email, password: password)
            }
            guard !(response.user.identities?.isEmpty ?? true) else {
                throw NSError(domain: "AuthClient", code: 409, userInfo: [:])
            }
            return response.user.id
        },
        setDisplayName: { userID, displayName in
            try await tracedSupabase("profiles.set_display_name") {
                try await supabase
                    .from("profiles")
                    .update(["display_name": displayName])
                    .eq("id", value: userID)
                    .execute()
                let profile: ProfileRow = try await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: userID)
                    .single()
                    .execute()
                    .value
                return profile.toUserProfile(id: userID)
            }
        },
        signOut: {
            try await tracedSupabase("auth.sign_out") {
                try await supabase.auth.signOut()
            }
        },
        currentSession: {
            guard let session = try? await supabase.auth.session else { return nil }
            let user = session.user
            do {
                let profile: ProfileRow = try await tracedSupabase("profiles.fetch_self") {
                    try await supabase
                        .from("profiles")
                        .select()
                        .eq("id", value: user.id)
                        .single()
                        .execute()
                        .value
                }
                return profile.toUserProfile(id: user.id)
            } catch {
                return UserProfile(
                    id: user.id,
                    displayName: (user.email ?? "").components(separatedBy: "@").first ?? ""
                )
            }
        },
        handleDeepLink: { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            // 註冊確認走 token_hash 流程：中間頁把 token_hash + type 以 query 帶進 deeplink，
            // 由 App 在此呼叫 verifyOtp「自己撕票」。token 直到這一刻才被消耗，
            // 所以電腦先點連結不會消耗它（見 createAccount 註解）。
            if let tokenHash = queryItems.first(where: { $0.name == "token_hash" })?.value {
                let typeRaw = queryItems.first(where: { $0.name == "type" })?.value ?? "signup"
                let otpType = EmailOTPType(rawValue: typeRaw) ?? .signup
                return try await tracedSupabase("auth.verify_otp") {
                    let session = try await supabase.auth.verifyOTP(tokenHash: tokenHash, type: otpType)
                    return session.user.id
                }
            }

            // 密碼重設仍走舊的 PKCE code 流程（resetPasswordForEmail → latergram://auth?type=recovery）。
            return try await tracedSupabase("auth.handle_deep_link") {
                let session = try await supabase.auth.session(from: url)
                return session.user.id
            }
        },
        sendPasswordReset: { email in
            try await tracedSupabase("auth.send_password_reset") {
                try await supabase.auth.resetPasswordForEmail(
                    email,
                    redirectTo: URL(string: "latergram://auth?type=recovery")!
                )
            }
        },
        updatePassword: { newPassword in
            _ = try await tracedSupabase("auth.update_password") {
                try await supabase.auth.update(user: .init(password: newPassword))
            }
        },
        deleteAccount: { appleAuthorizationCode in
            // 走 Edge Function（service role admin.deleteUser），刪 auth.users 一列
            // 後靠 DB cascade 清掉所有關聯資料。client 端無權直接刪 auth 使用者。
            // Apple 用戶會夾帶重新驗證取得的 authorizationCode，讓 server 撤銷 Apple 授權（5.1.1(v)）。
            _ = try await tracedSupabase("auth.delete_account") {
                let body = DeleteAccountBody(appleAuthorizationCode: appleAuthorizationCode)
                let _: DeleteAccountResponse = try await supabase.functions.invoke(
                    "delete-account",
                    options: FunctionInvokeOptions(body: body)
                )
            }
            // 帳號已刪，清掉本機殘留的 session（user 已不存在，忽略錯誤）
            try? await supabase.auth.signOut()
        },
        hasAppleIdentity: {
            guard let session = try? await supabase.auth.session else { return false }
            return session.user.identities?.contains { $0.provider == "apple" } ?? false
        }
    )

    static let testValue = AuthClient(
        signIn: { _, _ in UserProfile(displayName: "TestUser") },
        signInWithApple: { _, _ in AppleSignInResult(profile: UserProfile(displayName: "AppleUser"), needsDisplayName: true) },
        signUp: { _, _, displayName in UserProfile(displayName: displayName) },
        createAccount: { _, _ in UUID() },
        setDisplayName: { userID, displayName in UserProfile(id: userID, displayName: displayName) },
        signOut: {},
        currentSession: { nil },
        handleDeepLink: { _ in UUID() },
        sendPasswordReset: { _ in },
        updatePassword: { _ in },
        deleteAccount: { _ in },
        hasAppleIdentity: { false }
    )
}

// Apple 登入結果：帶回 profile，以及是否需要導到 setName 頁請使用者取名
// （首次註冊或既有未命名帳號 → true）。
struct AppleSignInResult: Equatable, Sendable {
    let profile: UserProfile
    let needsDisplayName: Bool
}

private struct DeleteAccountResponse: Decodable {
    let success: Bool
}

// 送給 delete-account 的 body；Apple 用戶帶 authorizationCode（server 據此撤銷授權）。
// email 用戶為 nil，會被編成 null，server 端視為一般刪除。
private struct DeleteAccountBody: Encodable, Sendable {
    let appleAuthorizationCode: String?
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

