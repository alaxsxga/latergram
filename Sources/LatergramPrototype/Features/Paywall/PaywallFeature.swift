import ComposableArchitecture
import StoreKit
import LatergramCore
import Foundation

@Reducer
struct PaywallFeature {
    @ObservableState
    struct State: Equatable {
        var products: [Product] = []
        var isLoading = false
        var productsLoadFailed = false
        var isPurchasing = false
        var isRestoring = false
        var isVerifyingEntitlement = false
        // 非 nil 表示開 paywall 時 verify 發現用戶已是 premium（另台裝置買了）
        // UI 切換成「已是 Premium」確認畫面，避免引導重複購買
        var alreadyPremiumProfile: UserProfile? = nil
        var errorMessage: String? = nil
    }

    enum Action {
        case onAppear
        case dismissTapped
        case errorDismissed
        case retryLoadProductsTapped
        case productsLoaded([Product])
        case purchaseTapped(Product)
        case restoreTapped
        case alreadyPremiumDismissTapped
        case _productsLoadFailed
        case _purchaseResult(Result<UserProfile, Error>)
        case _restoreResult(Result<UserProfile?, Error>)
        case _verifyResult(UserProfile?)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case purchaseSucceeded(UserProfile)
        }
    }

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.purchaseClient) var purchaseClient
    @Dependency(\.currentUserClient) var currentUserClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.opened")
                var effects: [Effect<Action>] = []
                if state.products.isEmpty, !state.isLoading {
                    state.isLoading = true
                    state.productsLoadFailed = false
                    effects.append(loadProducts())
                }
                // B2: 開 paywall 先確認另台裝置是否已訂閱，避免引導重複購買
                if !state.isVerifyingEntitlement, state.alreadyPremiumProfile == nil {
                    state.isVerifyingEntitlement = true
                    effects.append(.run { send in
                        let profile = try? await purchaseClient.verifyAndSyncEntitlement()
                        await send(._verifyResult(profile))
                    })
                }
                return .merge(effects)

            case ._verifyResult(let profile):
                state.isVerifyingEntitlement = false
                if let profile, profile.isPremium {
                    sentryClient.addBreadcrumb(
                        category: "paywall",
                        message: "paywall.already_premium_detected"
                    )
                    currentUserClient.update(profile)
                    state.alreadyPremiumProfile = profile
                }
                return .none

            case .alreadyPremiumDismissTapped:
                guard let profile = state.alreadyPremiumProfile else {
                    return .run { _ in await dismiss() }
                }
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .productsLoaded(let products):
                state.isLoading = false
                state.productsLoadFailed = false
                state.products = products
                return .none

            case ._productsLoadFailed:
                sentryClient.addBreadcrumb(
                    category: "paywall",
                    message: "paywall.products_load_failed",
                    level: .warning
                )
                state.isLoading = false
                state.productsLoadFailed = true
                return .none

            case .retryLoadProductsTapped:
                guard !state.isLoading else { return .none }
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.products_retry_tapped")
                state.isLoading = true
                state.productsLoadFailed = false
                return loadProducts()

            case .purchaseTapped(let product):
                sentryClient.addBreadcrumb(
                    category: "paywall",
                    message: "paywall.subscribe_tapped",
                    data: ["productID": product.id]
                )
                state.isPurchasing = true
                state.errorMessage = nil
                return .run { send in
                    await send(._purchaseResult(Result { try await purchaseClient.purchase(product) }))
                }

            case ._purchaseResult(.success(let profile)):
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.purchase_succeeded")
                state.isPurchasing = false
                currentUserClient.update(profile)
                return .send(.delegate(.purchaseSucceeded(profile)))

            case ._purchaseResult(.failure(let error)):
                let reason = purchaseFailureReason(error)
                sentryClient.addBreadcrumb(
                    category: "paywall",
                    message: "paywall.purchase_failed",
                    level: reason == "user_cancelled" ? .info : .warning,
                    data: ["reason": reason]
                )
                state.isPurchasing = false
                if let pe = error as? PurchaseError, pe == .userCancelled { return .none }
                state.errorMessage = error.localizedDescription
                return .none

            case .restoreTapped:
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.restore_tapped")
                state.isRestoring = true
                state.errorMessage = nil
                return .run { send in
                    await send(._restoreResult(Result { try await purchaseClient.restorePurchases() }))
                }

            case ._restoreResult(.success(.some(let profile))):
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.restore_succeeded")
                state.isRestoring = false
                currentUserClient.update(profile)
                return .send(.delegate(.purchaseSucceeded(profile)))

            case ._restoreResult(.success(.none)):
                sentryClient.addBreadcrumb(
                    category: "paywall",
                    message: "paywall.restore_empty",
                    level: .warning
                )
                state.isRestoring = false
                state.errorMessage = "找不到可還原的購買紀錄"
                return .none

            case ._restoreResult(.failure(let error)):
                sentryClient.addBreadcrumb(
                    category: "paywall",
                    message: "paywall.restore_failed",
                    level: .warning
                )
                state.isRestoring = false
                state.errorMessage = error.localizedDescription
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .dismissTapped:
                sentryClient.addBreadcrumb(category: "paywall", message: "paywall.dismissed")
                return .run { _ in await dismiss() }

            case .delegate:
                return .none
            }
        }
    }

    private func loadProducts() -> Effect<Action> {
        .run { send in
            do {
                let products = try await purchaseClient.fetchProducts()
                await send(.productsLoaded(products))
            } catch {
                await send(._productsLoadFailed)
            }
        }
    }

    private func purchaseFailureReason(_ error: Error) -> String {
        guard let pe = error as? PurchaseError else { return "other" }
        switch pe {
        case .userCancelled:      return "user_cancelled"
        case .pending:            return "pending"
        case .verificationFailed: return "verification_failed"
        case .notAuthenticated:   return "not_authenticated"
        case .timeout:            return "timeout"
        case .unknown:            return "unknown"
        }
    }
}
