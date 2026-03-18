import Auth
import ComposableArchitecture
import LatergramCore
import Foundation

@DependencyClient
struct AuthClient: Sendable {
    var signIn: @Sendable (_ email: String, _ password: String) async throws -> UserProfile
    var signUp: @Sendable (_ email: String, _ password: String) async throws -> UserProfile
    var signOut: @Sendable () async throws -> Void
    var currentSession: @Sendable () async -> UserProfile?
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
                username: profile.username
            )
        },
        signUp: { email, password in
            let response = try await supabase.auth.signUp(email: email, password: password)
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
                username: profile.username
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
                username: profile.username
            )
        }
    )

    static let testValue = AuthClient(
        signIn: { _, _ in UserProfile(displayName: "TestUser", username: "testuser") },
        signUp: { _, _ in UserProfile(displayName: "TestUser", username: "testuser") },
        signOut: {},
        currentSession: { nil }
    )
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

