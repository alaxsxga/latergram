import ComposableArchitecture
import Foundation

@DependencyClient
struct AppConfigClient: Sendable {
    var fetchMinIOSVersion: @Sendable () async throws -> String = { "0.0.0" }
}

extension AppConfigClient: DependencyKey {
    static let liveValue = AppConfigClient(
        fetchMinIOSVersion: {
            let rows: [AppConfigRow] = try await supabase
                .from("app_config")
                .select("key, value")
                .eq("key", value: "ios_min_version")
                .limit(1)
                .execute()
                .value
            return rows.first?.value ?? "0.0.0"
        }
    )
}

extension DependencyValues {
    var appConfigClient: AppConfigClient {
        get { self[AppConfigClient.self] }
        set { self[AppConfigClient.self] = newValue }
    }
}
