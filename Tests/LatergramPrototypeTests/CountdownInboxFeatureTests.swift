import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class CountdownInboxFeatureTests: XCTestCase {

    private let meID = UUID()
    private let friendID = UUID()

    // MARK: - messagesLoaded — 2-day filter on revealed messages

    func test_messagesLoaded_filtersRevealedOlderThan2Days() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 3600)

        let staleMessage = makeRevealedMessage(
            senderID: friendID, receiverID: meID,
            revealedAt: threeDaysAgo, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.messagesLoaded([staleMessage])) {
            $0.lastFetchedAt = now
            $0.lastNotificationRebuildAt = now
            // staleMessage is filtered out — messages stays empty
        }

        XCTAssertTrue(store.state.messages.isEmpty)
    }

    func test_messagesLoaded_keepsRevealedWithin2Days() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oneDayAgo = now.addingTimeInterval(-1 * 24 * 3600)

        let recentMessage = makeRevealedMessage(
            senderID: friendID, receiverID: meID,
            revealedAt: oneDayAgo, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([recentMessage]))

        XCTAssertNotNil(store.state.messages[id: recentMessage.id])
        XCTAssertEqual(store.state.messages[id: recentMessage.id]?.status, .revealed)
    }

    // MARK: - messagesLoaded — unrevealed messages are never filtered

    func test_messagesLoaded_keepsUnrevealedRegardlessOfAge() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fiveDaysAgo = now.addingTimeInterval(-5 * 24 * 3600)

        // scheduled but unlockAt is 5 days in the past — time has long passed
        let overdueMessage = makeScheduledMessage(
            senderID: friendID, receiverID: meID,
            unlockAt: fiveDaysAgo, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([overdueMessage]))

        // Message is kept (unrevealed regardless of age) and transitions to readyToReveal
        XCTAssertNotNil(store.state.messages[id: overdueMessage.id])
        XCTAssertEqual(store.state.messages[id: overdueMessage.id]?.status, .readyToReveal)
    }

    // MARK: - messagesLoaded — scheduled→readyToReveal transition

    func test_messagesLoaded_scheduledPastUnlockAt_becomesReadyToReveal() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let justPast = now.addingTimeInterval(-60)

        let scheduledMsg = makeScheduledMessage(
            senderID: friendID, receiverID: meID,
            unlockAt: justPast, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([scheduledMsg]))

        XCTAssertEqual(store.state.messages[id: scheduledMsg.id]?.status, .readyToReveal)
    }

    func test_messagesLoaded_scheduledFutureUnlockAt_remainsScheduled() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future = now.addingTimeInterval(3600)

        let scheduledMsg = makeScheduledMessage(
            senderID: friendID, receiverID: meID,
            unlockAt: future, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([scheduledMsg]))

        XCTAssertEqual(store.state.messages[id: scheduledMsg.id]?.status, .scheduled)
    }

    // MARK: - timerTick

    func test_timerTick_scheduledPastUnlockAt_transitionsToReadyToReveal() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let justPast = now.addingTimeInterval(-1)

        let scheduledMsg = makeScheduledMessage(
            senderID: friendID, receiverID: meID,
            unlockAt: justPast, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID
        state.messages = [scheduledMsg]
        state.now = now.addingTimeInterval(-1)  // one tick before

        let store = TestStore(initialState: state) { CountdownInboxFeature() }

        await store.send(.timerTick(now)) {
            $0.now = now
            $0.messages[id: scheduledMsg.id]?.status = .readyToReveal
        }
    }

    func test_timerTick_scheduledFutureUnlockAt_doesNotTransition() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future = now.addingTimeInterval(3600)

        let scheduledMsg = makeScheduledMessage(
            senderID: friendID, receiverID: meID,
            unlockAt: future, now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID
        state.messages = [scheduledMsg]
        state.now = now.addingTimeInterval(-1)

        let store = TestStore(initialState: state) { CountdownInboxFeature() }

        await store.send(.timerTick(now)) {
            $0.now = now
            // status stays .scheduled — no change
        }

        XCTAssertEqual(store.state.messages[id: scheduledMsg.id]?.status, .scheduled)
    }

    // MARK: - applySort (via messagesLoaded)

    func test_messagesLoaded_receivedPendingSort_expiredFirst() async {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let future  = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                           unlockAt: now.addingTimeInterval(3600), now: now)
        let expired = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                           unlockAt: now.addingTimeInterval(-60),  now: now)

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([future, expired]))

        // Expired message (readyToReveal) should appear first in receivedPendingSortOrder
        XCTAssertEqual(store.state.receivedPendingSortOrder.first, expired.id)
        XCTAssertEqual(store.state.receivedPendingSortOrder.last,  future.id)
    }

    func test_messagesLoaded_sentPendingSort_newerSentAtFirst() async {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let older = makeScheduledMessageWithSentAt(
            senderID: meID, receiverID: friendID,
            sentAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(7200), now: now
        )
        let newer = makeScheduledMessageWithSentAt(
            senderID: meID, receiverID: friendID,
            sentAt: now.addingTimeInterval(-900),
            unlockAt: now.addingTimeInterval(3600), now: now
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([older, newer]))

        // Newest sentAt first
        XCTAssertEqual(store.state.sentPendingSortOrder.first, newer.id)
        XCTAssertEqual(store.state.sentPendingSortOrder.last,  older.id)
    }

    func test_messagesLoaded_revealedSort_newerSentAtFirst() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let oneDayAgo = now.addingTimeInterval(-24 * 3600)

        let olderRevealed = makeRevealedMessageWithSentAt(
            senderID: friendID, receiverID: meID,
            sentAt: now.addingTimeInterval(-3600),
            revealedAt: oneDayAgo
        )
        let newerRevealed = makeRevealedMessageWithSentAt(
            senderID: friendID, receiverID: meID,
            sentAt: now.addingTimeInterval(-1800),
            revealedAt: oneDayAgo
        )

        var state = CountdownInboxFeature.State()
        state.currentUserID = meID

        let store = TestStore(initialState: state) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.messagesLoaded([olderRevealed, newerRevealed]))

        // Newest sentAt first
        XCTAssertEqual(store.state.revealedSortOrder.first, newerRevealed.id)
        XCTAssertEqual(store.state.revealedSortOrder.last,  olderRevealed.id)
    }

    // MARK: - revealResponse

    func test_revealResponse_true_setsRevealedStatus() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(-60), now: now)
        var initialState = CountdownInboxFeature.State()
        initialState.currentUserID = meID
        var readyMsg = msg
        readyMsg.status = .readyToReveal
        initialState.messages = [readyMsg]

        let store = TestStore(initialState: initialState) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messageClient.reveal = { _, _ in true }
        }
        store.exhaustivity = .off

        await store.send(.revealResponse(id: msg.id, result: true)) {
            $0.messages[id: msg.id]?.status = .revealed
            $0.messages[id: msg.id]?.revealedAt = now
        }
    }

    func test_revealResponse_false_setsTimeError() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(-60), now: now)
        var initialState = CountdownInboxFeature.State()
        var readyMsg = msg; readyMsg.status = .readyToReveal
        initialState.messages = [readyMsg]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }

        await store.send(.revealResponse(id: msg.id, result: false)) {
            $0.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
        }
    }

    func test_revealResponse_nil_setsNetworkError() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(-60), now: now)
        var initialState = CountdownInboxFeature.State()
        var readyMsg = msg; readyMsg.status = .readyToReveal
        initialState.messages = [readyMsg]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }

        await store.send(.revealResponse(id: msg.id, result: nil)) {
            $0.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
        }
    }

    func test_revealCommitFailed_rollsBackStatus() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(-60), now: now)
        var initialState = CountdownInboxFeature.State()
        var revealedMsg = msg
        revealedMsg.status = .revealed
        revealedMsg.revealedAt = now
        initialState.messages = [revealedMsg]

        let store = TestStore(initialState: initialState) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.revealCommitFailed(msg.id)) {
            $0.messages[id: msg.id]?.status = .readyToReveal
            $0.messages[id: msg.id]?.revealedAt = nil
            $0.errorMessage = "開啟失敗，請確認網路後再試"
        }
    }

    // MARK: - plusTapped

    func test_plusTapped_withCachedFriends_opensPickerWithoutFetch() async {
        let alice = Friend(displayName: "Alice", status: .accepted)
        var initialState = CountdownInboxFeature.State()
        initialState.currentUserID = meID
        initialState.friends = [alice]

        let store = TestStore(initialState: initialState) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.friendsCacheClient.load = { _ in [alice] }
        }

        await store.send(.plusTapped) {
            $0.showRecipientPicker = true
        }
    }

    func test_plusTapped_noFriends_opensPickerAndFetches() async {
        let alice = Friend(displayName: "Alice", status: .accepted)
        var initialState = CountdownInboxFeature.State()
        initialState.currentUserID = meID
        initialState.friends = []

        let store = TestStore(initialState: initialState) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [alice] }
        }

        await store.send(.plusTapped) {
            $0.showRecipientPicker = true
            $0.isLoadingFriends = true
        }
        await store.receive(\.friendsLoaded) {
            $0.isLoadingFriends = false
            $0.friends = [alice]
        }
    }

    // MARK: - revealTapped guard

    func test_revealTapped_scheduledMessage_doesNothing() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(3600), now: now)
        var initialState = CountdownInboxFeature.State()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }

        // No state change expected — guard returns .none for non-readyToReveal
        await store.send(.revealTapped(msg.id))
    }

    // MARK: - deleteResponse

    func test_deleteResponse_success_removesMessage() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(3600), now: now)
        var initialState = CountdownInboxFeature.State()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }

        await store.send(.deleteResponse(id: msg.id, error: nil)) {
            $0.messages = []
        }
    }

    func test_deleteResponse_failure_setsError() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: friendID, receiverID: meID,
                                       unlockAt: now.addingTimeInterval(3600), now: now)
        var initialState = CountdownInboxFeature.State()
        initialState.messages = [msg]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }

        await store.send(.deleteResponse(id: msg.id, error: "刪除失敗")) {
            $0.errorMessage = "刪除失敗"
        }
    }

    // MARK: - recipientSelected

    func test_recipientSelected_opensComposeForFriend() async {
        let alice = Friend(displayName: "Alice", status: .accepted)
        var initialState = CountdownInboxFeature.State()
        initialState.currentUserID = meID
        initialState.currentUserName = "Bob"
        initialState.showRecipientPicker = true
        initialState.friends = [alice]

        let store = TestStore(initialState: initialState) { CountdownInboxFeature() }
        store.exhaustivity = .off

        await store.send(.recipientSelected(alice)) {
            $0.showRecipientPicker = false
        }
        XCTAssertEqual(store.state.compose?.friend, alice)
        XCTAssertEqual(store.state.compose?.senderID, meID)
        XCTAssertEqual(store.state.compose?.senderName, "Bob")
    }

    // MARK: - messageSent

    func test_messageSent_appendsToMessages() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = makeScheduledMessage(senderID: meID, receiverID: friendID,
                                       unlockAt: now.addingTimeInterval(3600), now: now)
        let store = TestStore(initialState: CountdownInboxFeature.State()) {
            CountdownInboxFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.messageSent(msg)) {
            $0.messages = [msg]
            $0.receivedPendingSortOrder = [msg.id]
            $0.sentPendingSortOrder = [msg.id]
        }
    }
}

// MARK: - Helpers

private func makeScheduledMessage(
    senderID: UUID,
    receiverID: UUID,
    unlockAt: Date,
    now: Date
) -> DelayedMessage {
    DelayedMessage(
        senderID: senderID,
        receiverID: receiverID,
        senderName: "Sender",
        receiverName: "Receiver",
        body: "Test message",
        style: .classic,
        sentAt: now.addingTimeInterval(-3600),
        unlockAt: unlockAt,
        delaySeconds: 3600,
        status: .scheduled
    )
}

private func makeScheduledMessageWithSentAt(
    senderID: UUID,
    receiverID: UUID,
    sentAt: Date,
    unlockAt: Date,
    now: Date
) -> DelayedMessage {
    DelayedMessage(
        senderID: senderID,
        receiverID: receiverID,
        senderName: "Sender",
        receiverName: "Receiver",
        body: "Test message",
        style: .classic,
        sentAt: sentAt,
        unlockAt: unlockAt,
        delaySeconds: 3600,
        status: .scheduled
    )
}

private func makeRevealedMessageWithSentAt(
    senderID: UUID,
    receiverID: UUID,
    sentAt: Date,
    revealedAt: Date
) -> DelayedMessage {
    DelayedMessage(
        senderID: senderID,
        receiverID: receiverID,
        senderName: "Sender",
        receiverName: "Receiver",
        body: "Revealed message",
        style: .classic,
        sentAt: sentAt,
        unlockAt: revealedAt,
        delaySeconds: 3600,
        status: .revealed,
        revealedAt: revealedAt
    )
}

private func makeRevealedMessage(
    senderID: UUID,
    receiverID: UUID,
    revealedAt: Date,
    now: Date
) -> DelayedMessage {
    DelayedMessage(
        senderID: senderID,
        receiverID: receiverID,
        senderName: "Sender",
        receiverName: "Receiver",
        body: "Revealed message",
        style: .classic,
        sentAt: now.addingTimeInterval(-3600),
        unlockAt: revealedAt,
        delaySeconds: 3600,
        status: .revealed,
        revealedAt: revealedAt
    )
}
