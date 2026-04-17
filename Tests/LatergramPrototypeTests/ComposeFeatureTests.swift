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
        let store = TestStore(initialState: makeState(unlockAt: now.addingTimeInterval(30))) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.errorMessage = "解鎖時間至少 1 分鐘後"
        }
    }

    func test_submitTapped_unlockTooLate_setsError() async {
        let store = TestStore(initialState: makeState(unlockAt: now.addingTimeInterval(8 * 24 * 3600))) {
            ComposeFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.submitTapped) {
            $0.errorMessage = "解鎖時間最多 7 天後"
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
}
