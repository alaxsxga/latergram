import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class ChatDetailFeatureTests: XCTestCase {

    private let friend = Friend(displayName: "Bob", status: .accepted)
    private let meID = UUID()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeState() -> ChatDetailFeature.State {
        var s = ChatDetailFeature.State(friend: friend)
        s.currentUserID = meID
        s.senderName = "Alice"
        s.now = now
        return s
    }

    // MARK: - scheduledCountToFriend (computed property)

    func test_scheduledCountToFriend_onlyCountsCurrentUserScheduledAndFuture() {
        var state = makeState()

        // Counts: my scheduled + unlockAt > now
        let myScheduled = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        // Not counted: already readyToReveal
        let myReady = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(-1), status: .readyToReveal)
        // Not counted: sent by friend
        let friendScheduled = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        // Not counted: my scheduled but unlockAt in the past
        let myExpired = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(-60), status: .scheduled)

        state.messages = [myScheduled, myReady, friendScheduled, myExpired]

        XCTAssertEqual(state.scheduledCountToFriend, 1)
    }

    func test_isAtSendLimit_trueWhenScheduledCountMeetsLimit() async {
        let myScheduled = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)

        let store = TestStore(initialState: makeState()) {
            ChatDetailFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.currentUserClient.messageLimit = { 1 }
            $0.messagesCacheClient.save = { _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([myScheduled]))

        XCTAssertTrue(store.state.isAtSendLimit)
    }

    // MARK: - composeTapped

    func test_composeTapped_atLimit_setsShowLimitInfo() async {
        var initialState = makeState()
        initialState.messages = [
            makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        ]

        let store = TestStore(initialState: initialState) {
            ChatDetailFeature()
        } withDependencies: {
            $0.currentUserClient.messageLimit = { 1 }
        }

        await store.send(.composeTapped) {
            $0.isAtSendLimit = true
            $0.showLimitInfo = true
        }
        XCTAssertNil(store.state.compose)
    }

    func test_composeTapped_belowLimit_opensComposeSheet() async {
        let store = TestStore(initialState: makeState()) { ChatDetailFeature() }
        store.exhaustivity = .off

        await store.send(.composeTapped)

        XCTAssertNotNil(store.state.compose)
        XCTAssertNil(store.state.compose?.errorMessage)
    }

    // MARK: - messagesLoaded

    func test_messagesLoaded_sortsByUnlockAtAscending() async {
        let later  = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(7200), status: .scheduled)
        let sooner = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)

        let store = TestStore(initialState: makeState()) {
            ChatDetailFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messagesCacheClient.save = { _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([later, sooner]))

        XCTAssertEqual(Array(store.state.messages).map(\.id), [sooner.id, later.id])
    }

    func test_messagesLoaded_scheduledPastUnlockAt_becomesReadyToReveal() async {
        let overdue = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(-60), status: .scheduled)

        let store = TestStore(initialState: makeState()) {
            ChatDetailFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messagesCacheClient.save = { _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([overdue]))

        XCTAssertEqual(store.state.messages[id: overdue.id]?.status, .readyToReveal)
    }
    // MARK: - revealResponse

    func test_revealResponse_true_setsRevealedStatus() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(-60), status: .readyToReveal)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) {
            ChatDetailFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messageClient.reveal = { _, _ in true }
        }
        store.exhaustivity = .off

        await store.send(.revealResponse(id: msg.id, result: true)) {
            $0.messages[id: msg.id]?.status = MessageStatus.revealed
            $0.messages[id: msg.id]?.revealedAt = self.now
        }
    }

    func test_revealResponse_false_setsTimeError() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(-60), status: .readyToReveal)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.revealResponse(id: msg.id, result: false)) {
            $0.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
        }
    }

    func test_revealResponse_nil_setsNetworkError() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(-60), status: .readyToReveal)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.revealResponse(id: msg.id, result: nil)) {
            $0.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
        }
    }

    func test_revealCommitFailed_rollsBackStatus() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(-60), status: .revealed)
        var initialState = makeState()
        var revealedMsg = msg
        revealedMsg.revealedAt = now
        initialState.messages = [revealedMsg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.revealCommitFailed(msg.id)) {
            $0.messages[id: msg.id]?.status = .readyToReveal
            $0.messages[id: msg.id]?.revealedAt = nil
            $0.errorMessage = "開啟失敗，請確認網路後再試"
        }
    }

    // MARK: - revealTapped guard

    func test_revealTapped_scheduledMessage_doesNothing() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        // Guard returns .none for non-readyToReveal
        await store.send(.revealTapped(msg.id))
    }

    // MARK: - deleteResponse

    func test_deleteResponse_success_removesMessage() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.deleteResponse(id: msg.id, error: nil)) {
            $0.messages = []
        }
    }

    func test_deleteResponse_failure_setsError() async {
        let msg = makeMessage(senderID: friend.id, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        var initialState = makeState()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.deleteResponse(id: msg.id, error: "刪除失敗")) {
            $0.errorMessage = "刪除失敗"
        }
    }

    // MARK: - compose.sendSucceeded

    func test_composeSendSucceeded_appendsMessageAndSendsDelegate() async {
        let msg = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        var initialState = makeState()
        initialState.compose = ComposeFeature.State(
            friend: friend, senderID: meID, senderName: "Alice"
        )

        let store = TestStore(initialState: initialState) {
            ChatDetailFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messagesCacheClient.save = { _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.compose(.presented(.sendSucceeded(msg)))) {
            $0.compose = nil
            $0.messages = [msg]
        }
    }

    // MARK: - compose.sendFailed

    func test_composeSendFailed_limitExceeded_setsLimitError() async {
        var initialState = makeState()
        initialState.compose = ComposeFeature.State(
            friend: friend, senderID: meID, senderName: "Alice"
        )

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.compose(.presented(.sendFailed("friend_message_limit_exceeded")))) {
            $0.compose = nil
            $0.errorMessage = "已達上限，等訊息開啟後再傳"
        }
    }

    func test_composeSendFailed_other_setsRawError() async {
        var initialState = makeState()
        initialState.compose = ComposeFeature.State(
            friend: friend, senderID: meID, senderName: "Alice"
        )

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.compose(.presented(.sendFailed("network_error")))) {
            $0.compose = nil
            $0.errorMessage = "network_error"
        }
    }
}

// MARK: - Helpers

private func makeMessage(
    senderID: UUID,
    unlockAt: Date,
    status: MessageStatus
) -> DelayedMessage {
    DelayedMessage(
        senderID: senderID,
        receiverID: UUID(),
        senderName: "Sender",
        receiverName: "Receiver",
        body: "Test",
        style: .classic,
        sentAt: unlockAt.addingTimeInterval(-3600),
        unlockAt: unlockAt,
        delaySeconds: 3600,
        status: status
    )
}
