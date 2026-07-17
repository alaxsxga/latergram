import XCTest
import ComposableArchitecture
@testable import LatergramPrototype

@MainActor
final class OnboardingFeatureTests: XCTestCase {

    // MARK: - 頁面推進

    func test_nextTapped_notLastPage_advancesToNextPage() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }
        await store.send(.nextTapped) {
            $0.currentPage = 1
        }
    }

    func test_nextTapped_onLastPage_emitsFinished() async {
        var state = OnboardingFeature.State()
        state.currentPage = OnboardingFeature.pages.count - 1
        let store = TestStore(initialState: state) {
            OnboardingFeature()
        }
        await store.send(.nextTapped)
        await store.receive(\.delegate.finished)
    }

    // MARK: - 略過

    func test_skipTapped_emitsFinished() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }
        await store.send(.skipTapped)
        await store.receive(\.delegate.finished)
    }

    // MARK: - 滑動翻頁

    func test_pageChanged_updatesCurrentPage() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        }
        await store.send(.pageChanged(2)) {
            $0.currentPage = 2
        }
    }
}
