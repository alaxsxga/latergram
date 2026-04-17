import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class AppFeatureTests: XCTestCase {

    // MARK: - sessionChecked

    func test_sessionChecked_withUser_initializesChildStatesAndRoutesToMain() async {
        let user = UserProfile(id: UUID(), displayName: "Alice", username: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.sessionChecked(user)) {
            $0.currentUser = user
            $0.route = .main
            $0.friends.me = user
            $0.countdown.currentUserID = user.id
            $0.chats.currentUserID = user.id
            $0.chats.currentUserName = user.displayName
        }
    }

    func test_sessionChecked_nil_routesToAuth() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

        await store.send(.sessionChecked(nil)) {
            $0.route = .auth(AuthFeature.State())
        }
    }

    func test_sessionChecked_withPendingInviteCode_clearsCodeAndRoutesToFriends() async {
        let user = UserProfile(id: UUID(), displayName: "Alice", username: "alice")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let initialState = {
            var s = AppFeature.State()
            s.pendingInviteCode = "INVITE123"
            return s
        }()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.friendClient.acceptInvite = { _, _ in Friend(displayName: "Bob", status: .pending) }
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.sessionChecked(user)) {
            $0.currentUser = user
            $0.route = .main
            $0.pendingInviteCode = nil
            $0.selectedTab = .friends
        }
    }

    // MARK: - logoutSucceeded

    func test_logoutSucceeded_clearsAllState() async {
        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: UUID(), displayName: "Alice", username: "alice")
            s.route = .main
            s.selectedTab = .chats
            s.friends.me = UserProfile(displayName: "Alice", username: "alice")
            return s
        }()

        let store = TestStore(initialState: initialState) { AppFeature() }
        store.exhaustivity = .off

        await store.send(.friends(.logoutSucceeded))

        XCTAssertNil(store.state.currentUser)
        XCTAssertEqual(store.state.selectedTab, .countdown)
        XCTAssertTrue(store.state.friends.friends.isEmpty)
        XCTAssertTrue(store.state.countdown.messages.isEmpty)
        XCTAssertTrue(store.state.chats.latestMessages.isEmpty)
        if case .auth = store.state.route { } else {
            XCTFail("Expected route to be .auth after logout")
        }
    }

    // MARK: - countdown(.messagesLoaded) → chats aggregation

    func test_messagesLoaded_groupsByFriendID_picksLatestSentAt() async {
        let meID = UUID()
        let friendID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)

        let older = DelayedMessage(
            senderID: friendID, receiverID: meID,
            senderName: "Friend", receiverName: "Me",
            body: "Older",
            style: .classic,
            sentAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(-1800),
            status: .revealed,
            revealedAt: now.addingTimeInterval(-1800)
        )
        let newer = DelayedMessage(
            senderID: friendID, receiverID: meID,
            senderName: "Friend", receiverName: "Me",
            body: "Newer",
            style: .classic,
            sentAt: now.addingTimeInterval(-900),
            unlockAt: now.addingTimeInterval(-600),
            status: .revealed,
            revealedAt: now.addingTimeInterval(-600)
        )

        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: meID, displayName: "Me", username: "me")
            s.countdown.currentUserID = meID
            return s
        }()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.countdown(.messagesLoaded([older, newer])))
        await store.receive(\.chats.latestMessagesUpdated) {
            $0.chats.latestMessages = [friendID: newer]
        }

        XCTAssertEqual(store.state.chats.latestMessages[friendID], newer)
    }

    func test_messagesLoaded_sentAndReceivedSameFriend_picksLatestByFriendID() async {
        let meID = UUID()
        let friendID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)

        // I sent to friend (older)
        let sent = DelayedMessage(
            senderID: meID, receiverID: friendID,
            senderName: "Me", receiverName: "Friend",
            body: "I sent this",
            style: .classic,
            sentAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(-1),
            status: .revealed,
            revealedAt: now.addingTimeInterval(-1)
        )
        // Friend sent to me (newer)
        let received = DelayedMessage(
            senderID: friendID, receiverID: meID,
            senderName: "Friend", receiverName: "Me",
            body: "Friend sent this",
            style: .classic,
            sentAt: now.addingTimeInterval(-1800),
            unlockAt: now.addingTimeInterval(-900),
            status: .revealed,
            revealedAt: now.addingTimeInterval(-900)
        )

        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: meID, displayName: "Me", username: "me")
            s.countdown.currentUserID = meID
            return s
        }()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.countdown(.messagesLoaded([sent, received])))
        // Both belong to the same friendID; newer by sentAt is `received`
        await store.receive(\.chats.latestMessagesUpdated) {
            $0.chats.latestMessages = [friendID: received]
        }

        XCTAssertEqual(store.state.chats.latestMessages[friendID], received)
    }

    func test_messagesLoaded_nilCurrentUser_doesNotUpdateChats() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = DelayedMessage(
            senderID: UUID(), receiverID: UUID(),
            senderName: "A", receiverName: "B",
            body: "Hello",
            style: .classic,
            sentAt: now,
            unlockAt: now.addingTimeInterval(3600),
            status: .scheduled
        )

        // currentUser = nil (default, not logged in)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }
        store.exhaustivity = .off

        await store.send(.countdown(.messagesLoaded([msg])))

        // No .chats(.latestMessagesUpdated) should have been sent
        XCTAssertTrue(store.state.chats.latestMessages.isEmpty)
    }
}
