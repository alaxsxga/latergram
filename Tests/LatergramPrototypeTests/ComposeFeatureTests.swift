import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class ComposeFeatureTests: XCTestCase {

    private let friend = Friend(displayName: "Bob", status: .accepted)
    private let senderID = UUID()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeState(body: String = "Hello!", unlockAt: Date? = nil) -> ComposeFeature.State {
        var s = ComposeFeature.State(friend: friend, senderID: senderID, senderName: "Alice")
        s.body = body
        s.unlockAt = unlockAt ?? now.addingTimeInterval(3600)
        return s
    }

    // MARK: - submitTapped — validation → errorText mapping

    func test_submitTapped_emptyBody_setsError() async {
        let store = TestStore(initialState: makeState(body: "")) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.errorMessage = "訊息不可為空"
        }
    }

    func test_submitTapped_tooLongBody_setsError() async {
        let store = TestStore(initialState: makeState(body: String(repeating: "a", count: 1001))) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.errorMessage = "訊息不可超過 1000 字"
        }
    }

    func test_submitTapped_unlockTooSoon_setsError() async {
        var state = makeState(unlockAt: now.addingTimeInterval(30))
        state.timingMode = .unlockDate
        let store = TestStore(initialState: state) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.errorMessage = "解鎖時間至少 1 分鐘後"
        }
    }

    func test_submitTapped_over24h_nonPremium_showsPaywall() async {
        var state = makeState(unlockAt: now.addingTimeInterval(25 * 3600))
        state.timingMode = .unlockDate
        let store = TestStore(initialState: state) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.showLongDelayPaywall = true
        }
    }

    // MARK: - submitTapped — valid input

    func test_submitTapped_valid_setsSendingTrue() async {
        let store = TestStore(initialState: makeState()) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messageClient.send = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.submitTapped) {
            $0.isSending = true
            $0.errorMessage = nil
        }
    }

    // MARK: - premium bypass

    func test_submitTapped_over24h_premium_doesNotShowPaywall() async {
        var state = makeState(unlockAt: now.addingTimeInterval(25 * 3600))
        state.timingMode = .unlockDate
        state.isPremium = true

        let store = TestStore(initialState: state) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.messageClient.send = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.submitTapped) {
            $0.isSending = true
            $0.showLongDelayPaywall = false
        }
    }

    // MARK: - binding unlockAt > 24h triggers paywall immediately

    func test_binding_unlockAt_over24h_nonPremium_showsPaywall() async {
        let store = TestStore(initialState: makeState()) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.binding(.set(\.unlockAt, now.addingTimeInterval(25 * 3600)))) {
            $0.unlockAt = self.now.addingTimeInterval(25 * 3600)
            $0.showLongDelayPaywall = true
        }
    }

    // MARK: - sendFailed

    func test_sendFailed_setsErrorAndClearsSending() async {
        var state = makeState()
        state.isSending = true

        let store = TestStore(initialState: state) { ComposeFeature() }

        await store.send(.sendFailed("network_error")) {
            $0.isSending = false
            $0.errorMessage = "network_error"
        }
    }
}
