import XCTest
import LatergramCore
@testable import LatergramPrototype

final class RevealGateClientTests: XCTestCase {

    // testValue 用本地時間（now >= unlockAt）做判定，方便用 `$0.date = .constant(...)` 控制
    func test_testValue_canReveal_returnsBasedOnLocalTime() async {
        let client = RevealGateClient.testValue
        let unlockAt = Date(timeIntervalSince1970: 1_000_000)
        let msg = DelayedMessage(
            senderID: UUID(), receiverID: UUID(),
            senderName: "A", receiverName: "B",
            body: "hi",
            style: .classic,
            sentAt: unlockAt.addingTimeInterval(-3600),
            unlockAt: unlockAt,
            delaySeconds: 3600,
            status: .scheduled
        )

        let before = await client.canReveal(msg, unlockAt.addingTimeInterval(-1))
        XCTAssertEqual(before, false, "unlockAt 之前必須拒絕")

        let atUnlock = await client.canReveal(msg, unlockAt)
        XCTAssertEqual(atUnlock, true, "剛好 unlockAt 應放行")

        let after = await client.canReveal(msg, unlockAt.addingTimeInterval(1))
        XCTAssertEqual(after, true, "unlockAt 之後放行")
    }
}
