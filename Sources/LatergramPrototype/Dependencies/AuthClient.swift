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
                throw NSError(domain: "AuthClient", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "此 Email 已被註冊"])
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
        }
    )

    static let testValue = AuthClient(
        signIn: { _, _ in UserProfile(displayName: "TestUser") },
        signUp: { _, _, displayName in UserProfile(displayName: displayName) },
        createAccount: { _, _ in UUID() },
        setDisplayName: { userID, displayName in UserProfile(id: userID, displayName: displayName) },
        signOut: {},
        currentSession: { nil },
        handleDeepLink: { _ in UUID() }
    )
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

