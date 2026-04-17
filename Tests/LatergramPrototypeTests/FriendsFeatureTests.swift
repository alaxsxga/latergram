import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class FriendsFeatureTests: XCTestCase {

    // MARK: - remoteFriendsLoaded

    func test_remoteFriendsLoaded_changed_updatesStateAndSavesCache() async {
        let alice = Friend(displayName: "Alice", status: .accepted)
        let bob   = Friend(displayName: "Bob",   status: .accepted)

        nonisolated(unsafe) var savedFriends: [Friend]? = nil
        let store = TestStore(initialState: FriendsFeature.State()) {
            FriendsFeature()
        } withDependencies: {
            $0.friendsCacheClient.save = { friends, _ in savedFriends = friends }
        }
        store.exhaustivity = .off

        await store.send(.remoteFriendsLoaded([bob, alice]))

        // Sorted alphabetically: Alice, Bob
        XCTAssertEqual(store.state.friends.map(\.displayName), ["Alice", "Bob"])
        XCTAssertEqual(savedFriends?.map(\.displayName), ["Alice", "Bob"])
    }

    func test_remoteFriendsLoaded_unchanged_doesNotSaveCache() async {
        let alice = Friend(displayName: "Alice", status: .accepted)
        var initialState = FriendsFeature.State()
        initialState.friends = [alice]

        nonisolated(unsafe) var saveCalled = false
        let store = TestStore(initialState: initialState) {
            FriendsFeature()
        } withDependencies: {
            $0.friendsCacheClient.save = { _, _ in saveCalled = true }
        }
        store.exhaustivity = .off

        await store.send(.remoteFriendsLoaded([alice]))

        XCTAssertFalse(saveCalled)
        XCTAssertEqual(store.state.friends.map(\.displayName), ["Alice"])
    }

    // MARK: - inviteAccepted

    func test_inviteAccepted_appendsFriendSortedAlphabeticallyAndShowsBanner() async {
        let charlie = Friend(displayName: "Charlie", status: .accepted)
        var initialState = FriendsFeature.State()
        initialState.friends = [charlie]
        initialState.pastedInviteCode = "INVITE123"

        let alice = Friend(displayName: "Alice", status: .accepted)

        let store = TestStore(initialState: initialState) {
            FriendsFeature()
        }

        await store.send(.inviteAccepted(alice)) {
            $0.friends = [alice, charlie] // Alice < Charlie
            $0.pastedInviteCode = ""
            $0.banner = "好友已確認，可開始傳送訊息"
        }
    }

    // MARK: - acceptInviteCodeTapped — empty code validation

    func test_acceptInviteCodeTapped_emptyCode_setsBanner() async {
        var initialState = FriendsFeature.State()
        initialState.pastedInviteCode = "   " // whitespace only

        let store = TestStore(initialState: initialState) {
            FriendsFeature()
        }

        await store.send(.acceptInviteCodeTapped) {
            $0.banner = "邀請碼不可為空"
        }
    }
}
