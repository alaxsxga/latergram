import ComposableArchitecture
import LatergramCore
import Foundation

// MARK: - Store

final class CurrentUserStore: @unchecked Sendable {
    static let shared = CurrentUserStore()

    private let lock = NSLock()
    private var _user: UserProfile = UserProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        displayName: "",
        username: ""
    )

    var user: UserProfile {
        get { lock.withLock { _user } }
        set { lock.withLock { _user = newValue } }
    }
}

// MARK: - Dependency

extension DependencyValues {
    var currentUser: UserProfile {
        get { self[CurrentUserKey.self] }
        set { self[CurrentUserKey.self] = newValue }
    }
}

private enum CurrentUserKey: DependencyKey {
    static var liveValue: UserProfile {
        CurrentUserStore.shared.user
    }
    static let testValue = UserProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
        displayName: "TestUser",
        username: "testuser"
    )
}
