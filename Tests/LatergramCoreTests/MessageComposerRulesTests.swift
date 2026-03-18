import XCTest
@testable import LatergramCore

final class MessageComposerRulesTests: XCTestCase {
    func test_validate_rejectsTooShortDelay() {
        let rules = MessageComposerRules()
        let now = Date()
        let error = rules.validate(body: "hello", unlockAt: now.addingTimeInterval(10), now: now, lastSentAt: nil)
        XCTAssertEqual(error, .unlockTooSoon)
    }

    func test_validate_rejectsTooLongBody() {
        let rules = MessageComposerRules()
        let now = Date()
        let body = String(repeating: "a", count: 1001)
        let error = rules.validate(body: body, unlockAt: now.addingTimeInterval(120), now: now, lastSentAt: nil)
        XCTAssertEqual(error, .tooLong(max: 1000))
    }

    func test_validate_rejectsCooldown() {
        let rules = MessageComposerRules()
        let now = Date()
        let error = rules.validate(
            body: "hello",
            unlockAt: now.addingTimeInterval(120),
            now: now,
            lastSentAt: now.addingTimeInterval(-20)
        )

        guard case .cooldown = error else {
            XCTFail("Expected cooldown")
            return
        }
    }
}
