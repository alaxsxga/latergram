import XCTest
import ComposableArchitecture
import LatergramCore
import SwiftUI
@testable import LatergramPrototype

@MainActor
final class AppFeatureTests: XCTestCase {

    // MARK: - sessionChecked

    func test_sessionChecked_withUser_initializesChildStatesAndRoutesToMain() async {
        let user = UserProfile(id: UUID(), displayName: "Alice")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendsCacheClient.save = { _, _ in }
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
        let user = UserProfile(id: UUID(), displayName: "Alice")
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

    // MARK: - 首次啟用引導

    func test_sessionChecked_firstLaunch_presentsOnboarding() async {
        let user = UserProfile(id: UUID(), displayName: "Alice")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendsCacheClient.save = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.defaultAppStorage = defaults
        }
        store.exhaustivity = .off

        await store.send(.sessionChecked(user)) {
            $0.onboarding = OnboardingFeature.State()
        }
    }

    func test_sessionChecked_alreadySeenOnboarding_doesNotPresent() async {
        let user = UserProfile(id: UUID(), displayName: "Alice")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: AppFeature.hasSeenOnboardingKey)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendsCacheClient.save = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.defaultAppStorage = defaults
        }
        store.exhaustivity = .off

        await store.send(.sessionChecked(user)) {
            $0.route = .main
        }
        XCTAssertNil(store.state.onboarding)
    }

    func test_onboardingFinished_setsFlagAndDismisses() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var initial = AppFeature.State()
        initial.onboarding = OnboardingFeature.State()
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.defaultAppStorage = defaults
        }

        await store.send(.onboarding(.presented(.delegate(.finished)))) {
            $0.onboarding = nil
        }
        XCTAssertTrue(defaults.bool(forKey: AppFeature.hasSeenOnboardingKey))
    }

    // MARK: - logoutSucceeded

    func test_logoutSucceeded_clearsAllState() async {
        let alice = UserProfile(id: UUID(), displayName: "Alice")
        let bob = Friend(displayName: "Bob", status: .accepted)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = DelayedMessage(
            senderID: bob.id, receiverID: alice.id,
            senderName: "Bob", receiverName: "Alice",
            body: "hi",
            style: .classic,
            sentAt: now.addingTimeInterval(-60),
            unlockAt: now.addingTimeInterval(3600),
            delaySeconds: 3600,
            status: .scheduled
        )
        let initialState = {
            var s = AppFeature.State()
            s.currentUser = alice
            s.route = .main
            s.selectedTab = .chats
            s.friends.me = alice
            s.friends.friends = [bob]
            s.friends.path.append(SettingsFeature.State(me: alice))
            s.chats.friends = [bob]
            s.chats.latestMessages = [bob.id: msg]
            return s
        }()

        let store = TestStore(initialState: initialState) { AppFeature() }
        store.exhaustivity = .off

        let stackID = store.state.friends.path.ids[0]
        await store.send(.friends(.path(.element(id: stackID, action: .delegate(.logoutSucceeded)))))
        // logoutSucceeded dispatches .friends(.reset) / .chats(.reset) as Effects;
        // drain them so the resets are actually applied before we assert.
        await store.skipReceivedActions()

        XCTAssertNil(store.state.currentUser)
        XCTAssertEqual(store.state.selectedTab, .countdown)
        XCTAssertTrue(store.state.friends.friends.isEmpty)
        XCTAssertTrue(store.state.friends.path.isEmpty)
        XCTAssertTrue(store.state.countdown.messages.isEmpty)
        XCTAssertTrue(store.state.chats.latestMessages.isEmpty)
        if case .auth = store.state.route { } else {
            XCTFail("Expected route to be .auth after logout")
        }
    }

    // MARK: - accountDeleted

    func test_accountDeleted_clearsAllState() async {
        let alice = UserProfile(id: UUID(), displayName: "Alice")
        let bob = Friend(displayName: "Bob", status: .accepted)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let msg = DelayedMessage(
            senderID: bob.id, receiverID: alice.id,
            senderName: "Bob", receiverName: "Alice",
            body: "hi",
            style: .classic,
            sentAt: now.addingTimeInterval(-60),
            unlockAt: now.addingTimeInterval(3600),
            delaySeconds: 3600,
            status: .scheduled
        )
        let initialState = {
            var s = AppFeature.State()
            s.currentUser = alice
            s.route = .main
            s.selectedTab = .chats
            s.friends.me = alice
            s.friends.friends = [bob]
            s.friends.path.append(SettingsFeature.State(me: alice))
            s.chats.friends = [bob]
            s.chats.latestMessages = [bob.id: msg]
            return s
        }()

        let store = TestStore(initialState: initialState) { AppFeature() }
        store.exhaustivity = .off

        let stackID = store.state.friends.path.ids[0]
        await store.send(.friends(.path(.element(id: stackID, action: .delegate(.accountDeleted)))))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.currentUser)
        XCTAssertEqual(store.state.selectedTab, .countdown)
        XCTAssertTrue(store.state.friends.friends.isEmpty)
        XCTAssertTrue(store.state.friends.path.isEmpty)
        XCTAssertTrue(store.state.countdown.messages.isEmpty)
        XCTAssertTrue(store.state.chats.latestMessages.isEmpty)
        if case .auth = store.state.route { } else {
            XCTFail("Expected route to be .auth after account deletion")
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
            delaySeconds: 3600,
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
            delaySeconds: 3600,
            status: .revealed,
            revealedAt: now.addingTimeInterval(-600)
        )

        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: meID, displayName: "Me")
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
            delaySeconds: 3600,
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
            delaySeconds: 3600,
            status: .revealed,
            revealedAt: now.addingTimeInterval(-900)
        )

        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: meID, displayName: "Me")
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

    // MARK: - scenePhaseChanged

    func test_scenePhaseActive_inMain_callsVerifyAndSyncEntitlement() async {
        let meID = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let refreshed = UserProfile(id: meID, displayName: "Me", isPremium: true)

        let initialState = {
            var s = AppFeature.State()
            s.currentUser = UserProfile(id: meID, displayName: "Me", isPremium: false)
            s.route = .main
            return s
        }()

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.purchaseClient.verifyAndSyncEntitlement = { refreshed }
            // scenePhase=.active 也會觸發 countdown / chats / friends 的 foregroundRefresh
            $0.messageClient.fetchCountdownFeed = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [] }
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendsCacheClient.save = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.scenePhaseChanged(.active))
        await store.receive(\.profileRefreshed) {
            $0.currentUser = refreshed
        }
    }

    func test_scenePhaseActive_notInMain_doesNotVerify() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.purchaseClient.verifyAndSyncEntitlement = {
                XCTFail("不該在 route != .main 時呼叫 verify")
                return nil
            }
        }
        store.exhaustivity = .off

        // 預設 route = .splash，不該觸發 verify
        await store.send(.scenePhaseChanged(.active))
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
            delaySeconds: 3600,
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
