import ComposableArchitecture
import Foundation

enum BreadcrumbLevel: Sendable {
    case info
    case warning
    case error
}

@DependencyClient
struct SentryClient: Sendable {
    var identify: @Sendable (_ userID: UUID, _ displayName: String) -> Void
    var clearUser: @Sendable () -> Void
    var breadcrumb: @Sendable (
        _ category: String,
        _ message: String,
        _ level: BreadcrumbLevel,
        _ data: [String: String]?
    ) -> Void
}

extension SentryClient {
    func addBreadcrumb(
        category: String,
        message: String,
        level: BreadcrumbLevel = .info,
        data: [String: String]? = nil
    ) {
        self.breadcrumb(category, message, level, data)
    }
}

extension SentryClient: DependencyKey {
    static let liveValue: SentryClient = {
        #if os(iOS)
        return SentryClient(
            identify: { SentryBootstrap.identify(userID: $0, displayName: $1) },
            clearUser: { SentryBootstrap.clearUser() },
            breadcrumb: { category, message, level, data in
                SentryBootstrap.addBreadcrumb(
                    category: category,
                    message: message,
                    level: level.sentryLevel,
                    data: data
                )
            }
        )
        #else
        return SentryClient(
            identify: { _, _ in },
            clearUser: {},
            breadcrumb: { _, _, _, _ in }
        )
        #endif
    }()

    static let testValue = SentryClient(
        identify: { _, _ in },
        clearUser: {},
        breadcrumb: { _, _, _, _ in }
    )
}

extension DependencyValues {
    var sentryClient: SentryClient {
        get { self[SentryClient.self] }
        set { self[SentryClient.self] = newValue }
    }
}

#if os(iOS)
import Sentry

private extension BreadcrumbLevel {
    var sentryLevel: SentryLevel {
        switch self {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}
#endif
