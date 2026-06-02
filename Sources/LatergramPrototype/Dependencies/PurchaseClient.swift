import ComposableArchitecture
import StoreKit
import LatergramCore
import Foundation
import Functions

// MARK: - Product IDs

enum LatergramProduct {
    static let premiumMonthly = "com.ininder.ed.latergram.premium.monthly"
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
            // C3: 帶 appAccountToken，讓 server 端 JWS 驗證能比對「交易確實屬於這位用戶」
            let session = try await supabase.auth.session
            let userID = session.user.id
            let options: Set<Product.PurchaseOption> = [.appAccountToken(userID)]
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw PurchaseError.verificationFailed
                }
                // 先 sync 成功再 finish；失敗時 transaction 留著，下次 verifyAndSyncEntitlement 會從 currentEntitlements 撿回重試
                let profile = try await syncPremium(jws: verification.jwsRepresentation)
                await transaction.finish()
                return profile
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
            let session = try await supabase.auth.session
            let userID = session.user.id

            var validJWS: String? = nil
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil,
                      // 防禦：currentEntitlements 理論上只回有效訂閱，但 sandbox 可能殘留過期的
                      (transaction.expirationDate.map { $0 > Date() } ?? true)
                else { continue }
                // C3: 若 transaction 帶 appAccountToken，必須等於當前 user；未帶（legacy）暫時通過
                if let token = transaction.appAccountToken, token != userID { continue }
                validJWS = result.jwsRepresentation
                break
            }
            return try? await syncPremium(jws: validJWS)
        },
        restorePurchases: {
            try await AppStore.sync()
            let session = try await supabase.auth.session
            let userID = session.user.id
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      LatergramProduct.all.contains(transaction.productID),
                      transaction.revocationDate == nil,
                      (transaction.expirationDate.map { $0 > Date() } ?? true)
                else { continue }
                if let token = transaction.appAccountToken, token != userID { continue }
                return try await syncPremium(jws: result.jwsRepresentation)
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
                        guard let session = try? await supabase.auth.session else { continue }
                        let userID = session.user.id

                        // C3: 若 transaction 帶 appAccountToken，必須等於當前 user
                        if let token = transaction.appAccountToken, token != userID {
                            // 不屬於這位用戶的 transaction，跳過也不 finish（留給對應用戶下次登入處理）
                            continue
                        }

                        // 過期 transaction：finish() 後不打 server。server 會擋 400 expired 形成迴圈。
                        // 正式版自然到期會走這條；sandbox 殭屍 transaction（殘留未 finish）也由此清除。
                        // 真實 entitlement 狀態交給 verifyAndSyncEntitlement（foreground / 登入時呼叫）統一計算。
                        if let exp = transaction.expirationDate, exp < Date() {
                            await transaction.finish()
                            continue
                        }

                        let isActive = transaction.revocationDate == nil
                        let jws: String? = isActive ? result.jwsRepresentation : nil
                        // 先 sync 成功再 finish；失敗時保留 transaction，下次 verifyAndSyncEntitlement 會撿回
                        do {
                            let profile = try await syncPremium(jws: jws)
                            continuation.yield(profile)
                            await transaction.finish()
                        } catch {
                            // 留待下次 verify 重試
                        }
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

/// 呼叫 `sync-entitlement` Edge Function 同步 premium 狀態。
/// - 帶 `jws`：升級路徑（server 端驗證 Apple 簽章後寫入）
/// - 不帶 `jws`：降級路徑（client 已自驗證確認沒 entitlement）
private struct SyncEntitlementBody: Encodable, Sendable {
    let jws: String?
}

private func syncPremium(jws: String?) async throws -> UserProfile {
    let body = SyncEntitlementBody(jws: jws)
    let row: ProfileRow = try await supabase.functions.invoke(
        "sync-entitlement",
        options: FunctionInvokeOptions(body: body)
    )
    return row.toUserProfile()
}
