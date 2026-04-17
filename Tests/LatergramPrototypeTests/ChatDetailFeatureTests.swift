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
        state.userMessageLimit = 3

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
        XCTAssertFalse(state.isAtSendLimit)
    }

    func test_isAtSendLimit_trueWhenScheduledCountMeetsLimit() {
        var state = makeState()
        state.userMessageLimit = 1

        let myScheduled = makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        state.messages = [myScheduled]

        XCTAssertTrue(state.isAtSendLimit)
    }

    // MARK: - composeTapped

    func test_composeTapped_atLimit_setsShowLimitInfo() async {
        var initialState = makeState()
        initialState.userMessageLimit = 1
        initialState.messages = [
            makeMessage(senderID: meID, unlockAt: now.addingTimeInterval(3600), status: .scheduled)
        ]

        let store = TestStore(initialState: initialState) { ChatDetailFeature() }

        await store.send(.composeTapped) {
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
        status: status
    )
}
