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
            let session = try await supabase.auth.signIn(email: email, password: password)
            let profile: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: session.user.id)
                .single()
                .execute()
                .value
            return UserProfile(
                id: session.user.id,
                displayName: profile.display_name,
                username: profile.username,
                messageLimit: profile.message_limit ?? 1
            )
        },
        signUp: { email, password, displayName in
            let response = try await supabase.auth.signUp(email: email, password: password)
            try await supabase
                .from("profiles")
                .update(["display_name": displayName])
                .eq("id", value: response.user.id)
                .execute()
            let profile: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: response.user.id)
                .single()
                .execute()
                .value
            return UserProfile(
                id: response.user.id,
                displayName: profile.display_name,
                username: profile.username,
                messageLimit: profile.message_limit ?? 1
            )
        },
        createAccount: { email, password in
            let response = try await supabase.auth.signUp(email: email, password: password)
            guard !(response.user.identities?.isEmpty ?? true) else {
                throw NSError(domain: "AuthClient", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "此 Email 已被註冊"])
            }
            return response.user.id
        },
        setDisplayName: { userID, displayName in
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
            return UserProfile(
                id: userID,
                displayName: profile.display_name,
                username: profile.username,
                messageLimit: profile.message_limit ?? 1
            )
        },
        signOut: {
            try await supabase.auth.signOut()
        },
        currentSession: {
            guard let session = try? await supabase.auth.session else { return nil }
            let user = session.user
            guard let profile = try? await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value as ProfileRow
            else {
                return UserProfile(
                    id: user.id,
                    displayName: (user.email ?? "").components(separatedBy: "@").first ?? "",
                    username: (user.email ?? "").components(separatedBy: "@").first ?? ""
                )
            }
            return UserProfile(
                id: user.id,
                displayName: profile.display_name,
                username: profile.username,
                messageLimit: profile.message_limit ?? 1
            )
        },
        handleDeepLink: { url in
            let session = try await supabase.auth.session(from: url)
            return session.user.id
        }
    )

    static let testValue = AuthClient(
        signIn: { _, _ in UserProfile(displayName: "TestUser", username: "testuser") },
        signUp: { _, _, displayName in UserProfile(displayName: displayName, username: "testuser") },
        createAccount: { _, _ in UUID() },
        setDisplayName: { userID, displayName in UserProfile(id: userID, displayName: displayName, username: "testuser") },
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

