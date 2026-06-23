import XCTest
import Foundation
import Auth
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class AuthFeatureTests: XCTestCase {

    // MARK: - nextTapped — input validation

    func test_nextTapped_emptyEmail_setsError() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .signUp
            s.email = ""
            s.password = "password"
            s.passwordConfirmation = "password"
            return s
        }()) { AuthFeature() }

        await store.send(.nextTapped) {
            $0.errorMessage = "請填寫 Email 與密碼"
        }
    }

    func test_nextTapped_emptyPassword_setsError() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .signUp
            s.email = "test@example.com"
            s.password = ""
            s.passwordConfirmation = ""
            return s
        }()) { AuthFeature() }

        await store.send(.nextTapped) {
            $0.errorMessage = "請填寫 Email 與密碼"
        }
    }

    func test_nextTapped_passwordMismatch_setsError() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .signUp
            s.email = "test@example.com"
            s.password = "abc123"
            s.passwordConfirmation = "xyz456"
            return s
        }()) { AuthFeature() }

        await store.send(.nextTapped) {
            $0.errorMessage = "兩次密碼不一致"
        }
    }

    func test_nextTapped_success_transitionsToAwaitingConfirmation() async {
        let expectedID = UUID()
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .signUp
            s.email = "test@example.com"
            s.password = "password"
            s.passwordConfirmation = "password"
            return s
        }()) {
            AuthFeature()
        } withDependencies: {
            $0.authClient.createAccount = { _, _ in expectedID }
        }

        await store.send(.nextTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.accountCreated) {
            $0.isSubmitting = false
            $0.pendingUserID = expectedID
            $0.mode = .awaitingConfirmation
        }
    }

    func test_emailConfirmed_transitionsToSetName() async {
        let userID = UUID()
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .awaitingConfirmation
            s.pendingUserID = userID
            return s
        }()) {
            AuthFeature()
        }

        await store.send(.emailConfirmed(userID)) {
            $0.mode = .setName
            $0.pendingUserID = userID
        }
    }

    func test_nextTapped_createAccountFails_setsError() async {
        struct AccountError: Error, LocalizedError {
            var errorDescription: String? { "帳號建立失敗" }
        }
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .signUp
            s.email = "test@example.com"
            s.password = "password"
            s.passwordConfirmation = "password"
            return s
        }()) {
            AuthFeature()
        } withDependencies: {
            $0.authClient.createAccount = { _, _ in throw AccountError() }
        }

        await store.send(.nextTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.failed) {
            $0.isSubmitting = false
            // Non-Supabase errors are mapped to a generic localized message rather
            // than leaking the raw errorDescription. See localizedAuthErrorMessage.
            $0.errorMessage = LS("auth.error.generic")
        }
    }

    // MARK: - submitTapped — setName mode

    func test_submitSetName_emptyDisplayName_setsError() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .setName
            s.displayName = ""
            s.pendingUserID = UUID()
            return s
        }()) { AuthFeature() }

        await store.send(.submitTapped) {
            $0.errorMessage = "請填寫顯示名稱"
        }
    }

    func test_submitSetName_nilPendingUserID_setsError() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .setName
            s.displayName = "Alice"
            s.pendingUserID = nil
            return s
        }()) { AuthFeature() }

        await store.send(.submitTapped) {
            $0.errorMessage = "發生錯誤，請重新嘗試"
        }
    }

    // MARK: - submitTapped — resetPassword mode

    /// During recovery the session is already authenticated, so re-entering the
    /// existing password (GoTrue's `same_password` rejection) is treated as success.
    func test_submitReset_samePassword_treatedAsSuccess() async {
        let samePasswordError = AuthError.api(
            message: "New password should be different from the old password.",
            errorCode: .samePassword,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://example.supabase.co")!,
                statusCode: 422,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .resetPassword
            s.password = "samepass"
            s.passwordConfirmation = "samepass"
            return s
        }()) {
            AuthFeature()
        } withDependencies: {
            $0.authClient.updatePassword = { _ in throw samePasswordError }
            $0.authClient.currentSession = { UserProfile(displayName: "Alice") }
        }

        await store.send(.submitTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.succeeded) {
            $0.isSubmitting = false
        }
    }

    /// Any other update-password failure still surfaces an error to the user.
    func test_submitReset_otherError_setsError() async {
        struct ResetError: Error {}
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .resetPassword
            s.password = "brandnewpass"
            s.passwordConfirmation = "brandnewpass"
            return s
        }()) {
            AuthFeature()
        } withDependencies: {
            $0.authClient.updatePassword = { _ in throw ResetError() }
        }

        await store.send(.submitTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.failed) {
            $0.isSubmitting = false
            $0.errorMessage = LS("auth.error.generic")
        }
    }

    // MARK: - backTapped

    func test_backTapped_clearsStateAndReturnsToSignUp() async {
        let store = TestStore(initialState: {
            var s = AuthFeature.State()
            s.mode = .setName
            s.pendingUserID = UUID()
            s.displayName = "Alice"
            s.errorMessage = "Some error"
            return s
        }()) { AuthFeature() }

        await store.send(.backTapped) {
            $0.mode = .signUp
            $0.pendingUserID = nil
            $0.displayName = ""
            $0.errorMessage = nil
        }
    }
}
