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
        var isPurchasing = false
        var isRestoring = false
        var errorMessage: String? = nil
    }

    enum Action {
        case onAppear
        case dismissTapped
        case errorDismissed
        case productsLoaded([Product])
        case purchaseTapped(Product)
        case restoreTapped
        case _purchaseResult(Result<UserProfile, Error>)
        case _restoreResult(Result<UserProfile?, Error>)
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
                guard state.products.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                return .run { send in
                    let products = (try? await purchaseClient.fetchProducts()) ?? []
                    await send(.productsLoaded(products))
                }

            case .productsLoaded(let products):
                state.isLoading = false
                state.products = products
                return .none

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
}
