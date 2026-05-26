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
    var observeTransactionUpdates: @Sendable () -> AsyncStream<UserProfile> = { .finished }
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
                return try await syncPremium(true)
            case .userCancelled:
                throw PurchaseError.userCancelled
            case .pending:
                throw PurchaseError.pending
            @unknown default:
                throw PurchaseError.unknown
            }
        },
        verifyAndSyncEntitlement: {
            // 掃完 currentEntitlements 後依結果決定 promote 或 demote
            // 訂閱自然過期不會觸發 Transaction.updates，必須靠這裡每次登入/foreground 比對
            var hasEntitlement = false
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil
                else { continue }
                hasEntitlement = true
                break
            }
            return try? await syncPremium(hasEntitlement)
        },
        restorePurchases: {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil
                else { continue }
                return try await syncPremium(true)
            }
            return nil
        },
        observeTransactionUpdates: {
            AsyncStream { continuation in
                let task = Task {
                    for await result in Transaction.updates {
                        guard case .verified(let transaction) = result else { continue }
                        guard LatergramProduct.all.contains(transaction.productID) else {
                            await transaction.finish()
                            continue
                        }
                        // 未登入時不處理也不 finish，留給下次登入後的 verifyAndSyncEntitlement 撿
                        guard (try? await supabase.auth.session) != nil else { continue }

                        let isActive = transaction.revocationDate == nil
                        if let profile = try? await syncPremium(isActive) {
                            continuation.yield(profile)
                        }
                        await transaction.finish()
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )

    static let testValue = PurchaseClient(
        fetchProducts: { [] },
        purchase: { _ in UserProfile(displayName: "Test", username: "test") },
        verifyAndSyncEntitlement: { nil },
        restorePurchases: { nil },
        observeTransactionUpdates: { .finished }
    )
}

extension DependencyValues {
    var purchaseClient: PurchaseClient {
        get { self[PurchaseClient.self] }
        set { self[PurchaseClient.self] = newValue }
    }
}

// MARK: - Private Supabase helper

private func syncPremium(_ isPremium: Bool) async throws -> UserProfile {
    let session = try await supabase.auth.session
    let userID = session.user.id
    try await supabase
        .from("profiles")
        .update(["is_premium": isPremium])
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
