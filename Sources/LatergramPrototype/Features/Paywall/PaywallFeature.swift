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

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
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
                state.isLoading = false
                state.productsLoadFailed = true
                return .none

            case .retryLoadProductsTapped:
                guard !state.isLoading else { return .none }
                state.isLoading = true
                state.productsLoadFailed = false
                return loadProducts()

            case .purchaseTapped(let product):
                state.isPurchasing = true
                state.errorMessage = nil
                return .run { send in
                    await send(._purchaseResult(Result { try await purchaseClient.purchase(product) }))
                }

            case ._purchaseResult(.success(let profile)):
                state.isPurchasing = false
                currentUserClient.update(profile)
                return .send(.delegate(.purchaseSucceeded(profile)))

            case ._purchaseResult(.failure(let error)):
                state.isPurchasing = false
                if let pe = error as? PurchaseError, pe == .userCancelled { return .none }
                state.errorMessage = error.localizedDescription
                return .none

            case .restoreTapped:
                state.isRestoring = true
                state.errorMessage = nil
                return .run { send in
                    await send(._restoreResult(Result { try await purchaseClient.restorePurchases() }))
                }

            case ._restoreResult(.success(.some(let profile))):
                state.isRestoring = false
                currentUserClient.update(profile)
                return .send(.delegate(.purchaseSucceeded(profile)))

            case ._restoreResult(.success(.none)):
                state.isRestoring = false
                state.errorMessage = "找不到可還原的購買紀錄"
                return .none

            case ._restoreResult(.failure(let error)):
                state.isRestoring = false
                state.errorMessage = error.localizedDescription
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .dismissTapped:
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
}
