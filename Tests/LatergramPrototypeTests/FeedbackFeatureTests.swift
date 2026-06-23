import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class FeedbackFeatureTests: XCTestCase {

    private func makeUser(isPremium: Bool = false) -> UserProfile {
        UserProfile(id: UUID(), displayName: "Me", isPremium: isPremium)
    }

    private func makeState(content: String = "Love it") -> FeedbackFeature.State {
        var s = FeedbackFeature.State(me: makeUser())
        s.content = content
        return s
    }

    // MARK: - onAppear prefills email

    func test_onAppear_prefillsEmail() async {
        let store = TestStore(initialState: FeedbackFeature.State(me: makeUser())) {
            FeedbackFeature()
        } withDependencies: {
            $0.feedbackClient.currentEmail = { "me@example.com" }
        }

        await store.send(.onAppear)
        await store.receive(\.emailPrefilled) {
            $0.didPrefillEmail = true
            $0.contactEmail = "me@example.com"
        }
    }

    func test_onAppear_doesNotOverwriteExistingEmail() async {
        var state = FeedbackFeature.State(me: makeUser())
        state.contactEmail = "typed@example.com"
        let store = TestStore(initialState: state) {
            FeedbackFeature()
        } withDependencies: {
            $0.feedbackClient.currentEmail = { "auth@example.com" }
        }

        await store.send(.onAppear)
        await store.receive(\.emailPrefilled) {
            $0.didPrefillEmail = true // contactEmail stays "typed@example.com"
        }
    }

    // MARK: - submit success

    func test_submitTapped_success_emitsDelegate() async {
        let captured = LockIsolated<FeedbackSubmission?>(nil)
        let me = makeUser(isPremium: true)
        var state = FeedbackFeature.State(me: me)
        state.content = "  Great app  "
        state.category = .idea
        state.contactEmail = "me@example.com"

        let store = TestStore(initialState: state) {
            FeedbackFeature()
        } withDependencies: {
            $0.feedbackClient.submit = { captured.setValue($0) }
        }

        await store.send(.submitTapped) {
            $0.isSubmitting = true
        }
        await store.receive(\.submitSucceeded) {
            $0.isSubmitting = false
        }
        await store.receive(\.delegate.submitted)

        let submission = captured.value
        XCTAssertEqual(submission?.userID, me.id)
        XCTAssertEqual(submission?.category, "idea")
        XCTAssertEqual(submission?.content, "Great app") // trimmed
        XCTAssertEqual(submission?.contactEmail, "me@example.com")
        XCTAssertEqual(submission?.isPremium, true)
    }

    // MARK: - submit failure shows alert

    func test_submitTapped_failure_showsAlert() async {
        struct Boom: Error {}
        let store = TestStore(initialState: makeState()) {
            FeedbackFeature()
        } withDependencies: {
            $0.feedbackClient.submit = { _ in throw Boom() }
        }
        store.exhaustivity = .off

        await store.send(.submitTapped)
        await store.receive(\.submitFailed)

        XCTAssertFalse(store.state.isSubmitting)
        XCTAssertNotNil(store.state.alert)
    }

    // MARK: - canSubmit gating

    func test_submitTapped_emptyContent_doesNothing() async {
        let store = TestStore(initialState: makeState(content: "   ")) {
            FeedbackFeature()
        }

        await store.send(.submitTapped) // canSubmit == false → no state change, no effect
    }
}
