import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class SettingsFeatureTests: XCTestCase {

    private func makeUser() -> UserProfile {
        UserProfile(id: UUID(), displayName: "Me")
    }

    // MARK: - logoutConfirmTapped

    func test_logoutConfirmTapped_setsIsConfirming() async {
        let store = TestStore(initialState: SettingsFeature.State(me: makeUser())) {
            SettingsFeature()
        }

        await store.send(.logoutConfirmTapped) {
            $0.isConfirmingLogout = true
        }
    }

    // MARK: - logoutCancelled

    func test_logoutCancelled_clearsIsConfirming() async {
        var initial = SettingsFeature.State(me: makeUser())
        initial.isConfirmingLogout = true

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }

        await store.send(.logoutCancelled) {
            $0.isConfirmingLogout = false
        }
    }

    // MARK: - logoutTapped

    func test_logoutTapped_clearsConfirmingAndCallsAuthSignOutAndClearsCaches() async {
        let me = makeUser()
        var initial = SettingsFeature.State(me: me)
        initial.isConfirmingLogout = true

        let signOutCalled = LockIsolated(false)
        let friendsCacheCleared = LockIsolated<UUID?>(nil)
        let messagesCacheCleared = LockIsolated<UUID?>(nil)

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.authClient.signOut = { signOutCalled.setValue(true) }
            $0.friendsCacheClient.clear = { friendsCacheCleared.setValue($0) }
            $0.messagesCacheClient.clear = { messagesCacheCleared.setValue($0) }
        }

        await store.send(.logoutTapped) {
            $0.isConfirmingLogout = false
        }
        await store.receive(\.logoutSucceeded)
        await store.receive(\.delegate.logoutSucceeded)

        XCTAssertTrue(signOutCalled.value)
        XCTAssertEqual(friendsCacheCleared.value, me.id)
        XCTAssertEqual(messagesCacheCleared.value, me.id)
    }

    // MARK: - logoutSucceeded

    func test_logoutSucceeded_emitsDelegateLogoutSucceeded() async {
        let store = TestStore(initialState: SettingsFeature.State(me: makeUser())) {
            SettingsFeature()
        }

        await store.send(.logoutSucceeded)
        await store.receive(\.delegate.logoutSucceeded)
    }
}
