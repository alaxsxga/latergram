import ComposableArchitecture
import LatergramCore
import Foundation

// MARK: - Store

final class CurrentUserStore: @unchecked Sendable {
    static let shared = CurrentUserStore()

    private let lock = NSLock()
    private var _user: UserProfile = UserProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        displayName: ""
    )

    var user: UserProfile {
        get { lock.withLock { _user } }
        set { lock.withLock { _user = newValue } }
    }
}

// MARK: - Client

struct CurrentUserClient: Sendable {
    var isPremium: @Sendable () -> Bool
    var messageLimit: @Sendable () -> Int
    var maxDelaySeconds: @Sendable () -> Int
    var update: @Sendable (UserProfile) -> Void
}

extension CurrentUserClient: DependencyKey {
    static let liveValue = CurrentUserClient(
        isPremium: { CurrentUserStore.shared.user.isPremium },
        messageLimit: { CurrentUserStore.shared.user.messageLimit },
        maxDelaySeconds: { CurrentUserStore.shared.user.maxDelaySeconds },
        update: { CurrentUserStore.shared.user = $0 }
    )

    static let testValue = CurrentUserClient(
        isPremium: { false },
        messageLimit: { 1 },
        maxDelaySeconds: { 86400 },
        update: { _ in }
    )
}

extension DependencyValues {
    var currentUserClient: CurrentUserClient {
        get { self[CurrentUserClient.self] }
        set { self[CurrentUserClient.self] = newValue }
    }
}
