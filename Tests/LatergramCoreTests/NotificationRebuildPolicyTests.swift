import XCTest
@testable import LatergramCore

final class NotificationRebuildPolicyTests: XCTestCase {
    func test_shouldRebuild_respectsThrottle() {
        let policy = NotificationRebuildPolicy(cap: 64, throttleSeconds: 30)
        let now = Date()

        XCTAssertFalse(policy.shouldRebuild(lastRebuildAt: now.addingTimeInterval(-5), now: now))
        XCTAssertTrue(policy.shouldRebuild(lastRebuildAt: now.addingTimeInterval(-31), now: now))
    }

    func test_selectMessagesForScheduling_appliesCap() {
        let policy = NotificationRebuildPolicy(cap: 2, throttleSeconds: 30)
        let now = Date()
        let messages = (0..<3).map { idx in
            DelayedMessage(
                senderID: UUID(),
                receiverID: UUID(),
                senderName: "s\(idx)",
                body: "b",
                style: .classic,
                unlockAt: now.addingTimeInterval(TimeInterval(60 + idx))
            )
        }

        let selected = policy.selectMessagesForScheduling(messages, now: now)
        XCTAssertEqual(selected.count, 2)
    }
}
