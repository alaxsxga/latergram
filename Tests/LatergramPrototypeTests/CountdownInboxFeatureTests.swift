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
        status: .revealed,
        revealedAt: revealedAt
    )
}
