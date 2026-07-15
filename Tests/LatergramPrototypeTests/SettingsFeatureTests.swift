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

    // MARK: - deleteAccountConfirmTapped

    func test_deleteAccountConfirmTapped_setsIsConfirming() async {
        let store = TestStore(initialState: SettingsFeature.State(me: makeUser())) {
            SettingsFeature()
        }

        await store.send(.deleteAccountConfirmTapped) {
            $0.isConfirmingDeleteAccount = true
        }
    }

    // MARK: - deleteAccountCancelled

    func test_deleteAccountCancelled_clearsIsConfirming() async {
        var initial = SettingsFeature.State(me: makeUser())
        initial.isConfirmingDeleteAccount = true

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        }

        await store.send(.deleteAccountCancelled) {
            $0.isConfirmingDeleteAccount = false
        }
    }

    // MARK: - deleteAccountTapped（成功）

    func test_deleteAccountTapped_success_callsDeleteClearsCachesAndDelegates() async {
        let me = makeUser()
        var initial = SettingsFeature.State(me: me)
        initial.isConfirmingDeleteAccount = true

        let deleteCalled = LockIsolated(false)
        let friendsCacheCleared = LockIsolated<UUID?>(nil)
        let messagesCacheCleared = LockIsolated<UUID?>(nil)

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.authClient.deleteAccount = { _ in deleteCalled.setValue(true) }
            $0.friendsCacheClient.clear = { friendsCacheCleared.setValue($0) }
            $0.messagesCacheClient.clear = { messagesCacheCleared.setValue($0) }
        }

        await store.send(.deleteAccountTapped) {
            $0.isConfirmingDeleteAccount = false
            $0.isDeletingAccount = true
        }
        await store.receive(\.accountDeletionSucceeded) {
            $0.isDeletingAccount = false
        }
        await store.receive(\.delegate.accountDeleted)

        XCTAssertTrue(deleteCalled.value)
        XCTAssertEqual(friendsCacheCleared.value, me.id)
        XCTAssertEqual(messagesCacheCleared.value, me.id)
    }

    // MARK: - deleteAccountTapped（失敗）

    func test_deleteAccountTapped_failure_setsErrorAlertAndStopsSpinner() async {
        var initial = SettingsFeature.State(me: makeUser())
        initial.isConfirmingDeleteAccount = true

        struct DeleteError: Error {}

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.authClient.deleteAccount = { _ in throw DeleteError() }
        }

        await store.send(.deleteAccountTapped) {
            $0.isConfirmingDeleteAccount = false
            $0.isDeletingAccount = true
        }
        await store.receive(\.accountDeletionFailed) {
            $0.isDeletingAccount = false
            $0.deleteErrorAlert = AlertState {
                TextState(LS("settings.delete_account_error_title"))
            } actions: {
                ButtonState(role: .cancel) { TextState(LS("common.ok")) }
            } message: {
                TextState(LS("settings.delete_account_error_message"))
            }
        }
    }

    // MARK: - deleteAccountTapped（Apple 用戶 → 撤銷授權）

    func test_deleteAccountTapped_appleUser_reauthsAndPassesCode() async {
        var initial = SettingsFeature.State(me: makeUser())
        initial.isConfirmingDeleteAccount = true

        let passedCode = LockIsolated<String?>(nil)

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.authClient.hasAppleIdentity = { true }
            $0.appleReauthClient.authorizationCode = { "fresh-code" }
            $0.authClient.deleteAccount = { passedCode.setValue($0) }
            $0.friendsCacheClient.clear = { _ in }
            $0.messagesCacheClient.clear = { _ in }
        }

        await store.send(.deleteAccountTapped) {
            $0.isConfirmingDeleteAccount = false
            $0.isDeletingAccount = true
        }
        await store.receive(\.accountDeletionSucceeded) {
            $0.isDeletingAccount = false
        }
        await store.receive(\.delegate.accountDeleted)

        XCTAssertEqual(passedCode.value, "fresh-code")
    }

    // MARK: - deleteAccountTapped（Apple 重新驗證被取消 → 靜默中止）

    func test_deleteAccountTapped_appleReauthCancelled_abortsSilently() async {
        var initial = SettingsFeature.State(me: makeUser())
        initial.isConfirmingDeleteAccount = true

        let deleteCalled = LockIsolated(false)

        let store = TestStore(initialState: initial) {
            SettingsFeature()
        } withDependencies: {
            $0.authClient.hasAppleIdentity = { true }
            $0.appleReauthClient.authorizationCode = { throw CancellationError() }
            $0.authClient.deleteAccount = { _ in deleteCalled.setValue(true) }
        }

        await store.send(.deleteAccountTapped) {
            $0.isConfirmingDeleteAccount = false
            $0.isDeletingAccount = true
        }
        await store.receive(\.accountDeletionCancelled) {
            $0.isDeletingAccount = false
        }

        XCTAssertFalse(deleteCalled.value)
    }
}
