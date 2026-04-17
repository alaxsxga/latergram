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
}
