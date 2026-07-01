import Auth
import ComposableArchitecture
import LatergramCore
import Foundation

@DependencyClient
struct AuthClient: Sendable {
    var signIn: @Sendable (_ email: String, _ password: String) async throws -> UserProfile
    var signUp: @Sendable (_ email: String, _ password: String, _ displayName: String) async throws -> UserProfile
    var createAccount: @Sendable (_ email: String, _ password: String) async throws -> UUID
    var setDisplayName: @Sendable (_ userID: UUID, _ displayName: String) async throws -> UserProfile
    var signOut: @Sendable () async throws -> Void
    var currentSession: @Sendable () async -> UserProfile?
    var handleDeepLink: @Sendable (_ url: URL) async throws -> UUID
    var sendPasswordReset: @Sendable (_ email: String) async throws -> Void
    var updatePassword: @Sendable (_ newPassword: String) async throws -> Void
    var deleteAccount: @Sendable () async throws -> Void
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
            try await tracedSupabase("auth.handle_deep_link") {
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
        deleteAccount: {
            // 走 Edge Function（service role admin.deleteUser），刪 auth.users 一列
            // 後靠 DB cascade 清掉所有關聯資料。client 端無權直接刪 auth 使用者。
            _ = try await tracedSupabase("auth.delete_account") {
                let _: DeleteAccountResponse = try await supabase.functions.invoke("delete-account")
            }
            // 帳號已刪，清掉本機殘留的 session（user 已不存在，忽略錯誤）
            try? await supabase.auth.signOut()
        }
    )

    static let testValue = AuthClient(
        signIn: { _, _ in UserProfile(displayName: "TestUser") },
        signUp: { _, _, displayName in UserProfile(displayName: displayName) },
        createAccount: { _, _ in UUID() },
        setDisplayName: { userID, displayName in UserProfile(id: userID, displayName: displayName) },
        signOut: {},
        currentSession: { nil },
        handleDeepLink: { _ in UUID() },
        sendPasswordReset: { _ in },
        updatePassword: { _ in },
        deleteAccount: {}
    )
}

private struct DeleteAccountResponse: Decodable {
    let success: Bool
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

