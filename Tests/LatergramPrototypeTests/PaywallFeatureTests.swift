import XCTest
import ComposableArchitecture
import LatergramCore
@testable import LatergramPrototype

@MainActor
final class PaywallFeatureTests: XCTestCase {

    private func makeUser(isPremium: Bool) -> UserProfile {
        UserProfile(id: UUID(), displayName: "Me", isPremium: isPremium)
    }

    // MARK: - onAppear

    // 開 paywall 時應同時跑 fetchProducts + verifyAndSyncEntitlement，
    // verify 是 B2 用來避免另台裝置已訂閱還引導重複購買。
    func test_onAppear_kicksOffBothFetchAndVerify() async {
        let store = TestStore(initialState: PaywallFeature.State()) {
            PaywallFeature()
        } withDependencies: {
            $0.purchaseClient.fetchProducts = { [] }
            $0.purchaseClient.verifyAndSyncEntitlement = { nil }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.productsLoadFailed = false
            $0.isVerifyingEntitlement = true
        }
        await store.receive(\.productsLoaded) {
            $0.isLoading = false
            $0.products = []
        }
        await store.receive(\._verifyResult) {
            $0.isVerifyingEntitlement = false
        }
    }

    // MARK: - _verifyResult

    func test_verifyResult_premium_setsAlreadyPremiumProfileAndUpdatesCurrentUser() async {
        let premiumUser = makeUser(isPremium: true)
        var initial = PaywallFeature.State()
        initial.isVerifyingEntitlement = true

        let updatedProfile = LockIsolated<UserProfile?>(nil)
        let store = TestStore(initialState: initial) {
            PaywallFeature()
        } withDependencies: {
            $0.currentUserClient.update = { updatedProfile.setValue($0) }
        }

        await store.send(._verifyResult(premiumUser)) {
            $0.isVerifyingEntitlement = false
            $0.alreadyPremiumProfile = premiumUser
        }

        XCTAssertEqual(updatedProfile.value, premiumUser)
    }

    func test_verifyResult_notPremium_keepsNormalPaywall() async {
        var initial = PaywallFeature.State()
        initial.isVerifyingEntitlement = true

        let updateCalled = LockIsolated(false)
        let store = TestStore(initialState: initial) {
            PaywallFeature()
        } withDependencies: {
            $0.currentUserClient.update = { _ in updateCalled.setValue(true) }
        }

        await store.send(._verifyResult(nil)) {
            $0.isVerifyingEntitlement = false
        }

        XCTAssertFalse(updateCalled.value, "非 premium 不應改 currentUserClient")
        XCTAssertNil(store.state.alreadyPremiumProfile)
    }

    // MARK: - alreadyPremiumDismissTapped

    func test_alreadyPremiumDismissTapped_sendsPurchaseSucceededDelegate() async {
        let premiumUser = makeUser(isPremium: true)
        var initial = PaywallFeature.State()
        initial.alreadyPremiumProfile = premiumUser

        let store = TestStore(initialState: initial) {
            PaywallFeature()
        }

        await store.send(.alreadyPremiumDismissTapped)
        await store.receive(\.delegate.purchaseSucceeded)
    }

    // MARK: - fetchProducts failure

    // fetchProducts throw 應走 ._productsLoadFailed 顯示重試按鈕（D4）
    // 註：PurchaseClient.liveValue 在「空陣列」時也會主動 throw（防 StoreKit 真機斷網
    // 不 throw 直接回 [] 的 case），對 reducer 而言與此 case 為同一路徑。
    func test_fetchProducts_throws_setsProductsLoadFailed() async {
        struct FakeError: Error {}
        let store = TestStore(initialState: PaywallFeature.State()) {
            PaywallFeature()
        } withDependencies: {
            $0.purchaseClient.fetchProducts = { throw FakeError() }
            $0.purchaseClient.verifyAndSyncEntitlement = { nil }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
            $0.productsLoadFailed = false
            $0.isVerifyingEntitlement = true
        }
        await store.receive(\._productsLoadFailed) {
            $0.isLoading = false
            $0.productsLoadFailed = true
        }
        await store.receive(\._verifyResult) {
            $0.isVerifyingEntitlement = false
        }
    }

    // MARK: - retryLoadProductsTapped

    func test_retryLoadProductsTapped_refiresFetchAndClearsFailure() async {
        var initial = PaywallFeature.State()
        initial.productsLoadFailed = true
        initial.isLoading = false

        let store = TestStore(initialState: initial) {
            PaywallFeature()
        } withDependencies: {
            $0.purchaseClient.fetchProducts = { [] }
        }

        await store.send(.retryLoadProductsTapped) {
            $0.isLoading = true
            $0.productsLoadFailed = false
        }
        await store.receive(\.productsLoaded) {
            $0.isLoading = false
            $0.products = []
        }
    }
}
