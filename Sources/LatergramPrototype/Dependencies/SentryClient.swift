import ComposableArchitecture
import Foundation

@DependencyClient
struct SentryClient: Sendable {
    var identify: @Sendable (_ userID: UUID, _ displayName: String) -> Void
    var clearUser: @Sendable () -> Void
}

extension SentryClient: DependencyKey {
    static let liveValue: SentryClient = {
        #if os(iOS)
        return SentryClient(
            identify: { SentryBootstrap.identify(userID: $0, displayName: $1) },
            clearUser: { SentryBootstrap.clearUser() }
        )
        #else
        return SentryClient(identify: { _, _ in }, clearUser: {})
        #endif
    }()

    static let testValue = SentryClient(
        identify: { _, _ in },
        clearUser: {}
    )
}

extension DependencyValues {
    var sentryClient: SentryClient {
        get { self[SentryClient.self] }
        set { self[SentryClient.self] = newValue }
    }
}
