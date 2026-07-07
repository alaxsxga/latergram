import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class ChatsFeatureTests: XCTestCase {

    // MARK: - friendsLoaded

    func test_friendsLoaded_filtersOutNonAccepted() async {
        let accepted = Friend(displayName: "Alice", status: .accepted)
        let pending  = Friend(displayName: "Bob",   status: .pending)
        let rejected = Friend(displayName: "Carol", status: .rejected)

        let store = TestStore(initialState: ChatsFeature.State()) {
            ChatsFeature()
        }

        await store.send(.friendsLoaded([accepted, pending, rejected])) {
            $0.isLoading = false
            $0.friends = [accepted]
        }
    }

    func test_friendsLoaded_emptyList_clearsState() async {
        var initialState = ChatsFeature.State()
        initialState.friends = [Friend(displayName: "Alice", status: .accepted)]
        initialState.isLoading = true

        let store = TestStore(initialState: initialState) {
            ChatsFeature()
        }

        await store.send(.friendsLoaded([])) {
            $0.isLoading = false
            $0.friends = []
        }
    }

    // MARK: - onAppear — sync from shared friends cache

    func test_onAppear_nonEmptyFriends_syncsFromCacheWithoutFetch() async {
        // A friend added on the Friends tab lands in the shared cache; re-appearing
        // must pick it up without a remote fetch.
        let alice = Friend(displayName: "Alice", status: .accepted)
        let bob   = Friend(displayName: "Bob",   status: .accepted)
        let pending = Friend(displayName: "Carol", status: .pending)

        var initialState = ChatsFeature.State()
        initialState.friends = [alice]

        let store = TestStore(initialState: initialState) {
            ChatsFeature()
        } withDependencies: {
            $0.friendsCacheClient.load = { _ in [alice, bob, pending] }
        }

        await store.send(.onAppear) {
            $0.friends = [alice, bob] // pending filtered out; no isLoading, no fetch
        }
    }

    func test_onAppear_emptyFriendsAndCache_fetchesRemote() async {
        let alice = Friend(displayName: "Alice", status: .accepted)

        let store = TestStore(initialState: ChatsFeature.State()) {
            ChatsFeature()
        } withDependencies: {
            $0.friendsCacheClient.load = { _ in [] }
            $0.friendClient.fetchFriends = { _ in [alice] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.friendsLoaded) {
            $0.isLoading = false
            $0.friends = [alice]
        }
    }
}
