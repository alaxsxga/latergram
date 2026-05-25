import ComposableArchitecture
import StoreKit
import LatergramCore
import Foundation

// MARK: - Product IDs

enum LatergramProduct {
    static let premiumMonthly = "com.ininder.latergram.premium.monthly"
    static let all: [String] = [premiumMonthly]
}

// MARK: - Errors

enum PurchaseError: LocalizedError, Equatable {
    case verificationFailed
    case userCancelled
    case pending
    case notAuthenticated
    case unknown

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "購買驗證失敗，請稍後再試"
        case .userCancelled:     return nil
        case .pending:           return "購買待審核中"
        case .notAuthenticated:  return "請先登入"
        case .unknown:           return "未知錯誤，請稍後再試"
        }
    }
}

// MARK: - Client

@DependencyClient
struct PurchaseClient: Sendable {
    var fetchProducts: @Sendable () async throws -> [Product]
    var purchase: @Sendable (_ product: Product) async throws -> UserProfile
    var verifyAndSyncEntitlement: @Sendable () async throws -> UserProfile?
    var restorePurchases: @Sendable () async throws -> UserProfile?
}

extension PurchaseClient: DependencyKey {
    static let liveValue = PurchaseClient(
        fetchProducts: {
            let products = try await Product.products(for: LatergramProduct.all)
            return products.sorted { $0.price < $1.price }
        },
        purchase: { product in
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw PurchaseError.verificationFailed
                }
                await transaction.finish()
                return try await syncPremiumToSupabase()
            case .userCancelled:
                throw PurchaseError.userCancelled
            case .pending:
                throw PurchaseError.pending
            @unknown default:
                throw PurchaseError.unknown
            }
        },
        verifyAndSyncEntitlement: {
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil
                else { continue }
                return try? await syncPremiumToSupabase()
            }
            return nil
        },
        restorePurchases: {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil
                else { continue }
                return try await syncPremiumToSupabase()
            }
            return nil
        }
    )

    static let testValue = PurchaseClient(
        fetchProducts: { [] },
        purchase: { _ in UserProfile(displayName: "Test", username: "test") },
        verifyAndSyncEntitlement: { nil },
        restorePurchases: { nil }
    )
}

extension DependencyValues {
    var purchaseClient: PurchaseClient {
        get { self[PurchaseClient.self] }
        set { self[PurchaseClient.self] = newValue }
    }
}

// MARK: - Private Supabase helper

private func syncPremiumToSupabase() async throws -> UserProfile {
    let session = try await supabase.auth.session
    let userID = session.user.id
    try await supabase
        .from("profiles")
        .update(["is_premium": true])
        .eq("id", value: userID)
        .execute()
    let profile: ProfileRow = try await supabase
        .from("profiles")
        .select()
        .eq("id", value: userID)
        .single()
        .execute()
        .value
    return profile.toUserProfile(id: userID)
}
