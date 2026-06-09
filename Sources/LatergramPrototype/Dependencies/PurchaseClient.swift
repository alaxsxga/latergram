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
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "購買驗證失敗，請稍後再試"
        case .userCancelled:     return nil
        case .pending:           return "購買待審核中"
        case .notAuthenticated:  return "請先登入"
        case .timeout:           return "連線逾時，請稍後再試"
        case .unknown:           return "未知錯誤，請稍後再試"
        }
    }
}

// fetchProducts / verifyAndSyncEntitlement 都需要明確 client-side timeout：
// - `Product.products(for:)` 在斷網真機可能等到 URLSession 預設 timeout（~60s）才放棄
// - `syncPremium` 打 Edge Function，斷網時同樣可能 hang
// 由 client 10 秒強制 race 失敗，讓 paywall 不會被任何一邊卡住而無法顯示 retry。
private let purchaseNetworkTimeout: Duration = .seconds(10)

// MARK: - Decision models（pure，可 unit test）

/// 從 StoreKit `Transaction` 抽出純資料的 snapshot，讓決策邏輯不需依賴無法 mock 的 StoreKit 型別。
struct EntitlementSnapshot: Equatable, Sendable {
    let productID: String
    let revocationDate: Date?
    let expirationDate: Date?
    let appAccountToken: UUID?
    let jws: String
}

enum ReconcileDecision: Equatable, Sendable {
    case promote(jws: String)
    case demote
}

enum TransactionUpdateDecision: Equatable, Sendable {
    /// 不屬於當前 user 或未登入 — 不 sync 也不 finish（留給下次機會處理）
    case skip
    /// 過期或不認得的 productID — finish 清理但不打 server
    case finishWithoutSync
    /// 正常路徑 — 呼叫 sync(jws)，成功才 finish；jws=nil 代表 revoked 走降級
    case sync(jws: String?)
}

// MARK: - Pure helpers

/// 給定當前所有 entitlement 與 user，決定該 promote（帶 jws 升級）還是 demote。
/// 過濾：非本 app product、已 revoke、已過期、appAccountToken 不屬於本 user。
func reconcileEntitlement(
    entitlements: [EntitlementSnapshot],
    userID: UUID,
    now: Date
) -> ReconcileDecision {
    for ent in entitlements {
        guard LatergramProduct.all.contains(ent.productID),
              ent.revocationDate == nil,
              (ent.expirationDate.map { $0 > now } ?? true)
        else { continue }
        if let token = ent.appAccountToken, token != userID { continue }
        return .promote(jws: ent.jws)
    }
    return .demote
}

/// 給定 `Transaction.updates` 收到的單筆 transaction 屬性，決定如何處理。
/// - 不認得的 productID → finishWithoutSync（清掉）
/// - 未登入 → skip（不 finish，等下次登入）
/// - appAccountToken 不屬於本 user → skip（不 finish，留給對應用戶）
/// - 過期 → finishWithoutSync（清掉，server 會擋 expired 400）
/// - 否則 → sync(jws)；revoked 走 jws=nil 降級
func transactionUpdateDecision(
    productID: String,
    revocationDate: Date?,
    expirationDate: Date?,
    appAccountToken: UUID?,
    userID: UUID?,
    now: Date,
    jws: String
) -> TransactionUpdateDecision {
    guard LatergramProduct.all.contains(productID) else { return .finishWithoutSync }
    guard let userID else { return .skip }
    if let token = appAccountToken, token != userID { return .skip }
    if let exp = expirationDate, exp < now { return .finishWithoutSync }
    let isActive = revocationDate == nil
    return .sync(jws: isActive ? jws : nil)
}

/// 先 sync 成功才 finish；sync 失敗會 throw 且不 finish — 讓 transaction 保留，下次 verify 再撿。
/// 用於需要把 sync 錯誤往上拋的路徑（如 user 觸發的 purchase）。
func syncThenFinish(
    jws: String?,
    sync: (_ jws: String?) async throws -> UserProfile,
    finish: () async -> Void
) async throws -> UserProfile {
    let profile = try await sync(jws)
    await finish()
    return profile
}

/// 依 decision 執行 side effects，回傳「該 yield 到 stream 的 profile」。
/// - `.skip` / `.finishWithoutSync` / sync 失敗：回 nil（不 yield）
/// - 只有 sync 成功才 finish 然後 yield；sync throw 時不 finish（留給下次 verify 撿）
func processTransactionUpdate(
    decision: TransactionUpdateDecision,
    sync: (_ jws: String?) async throws -> UserProfile,
    finish: () async -> Void
) async -> UserProfile? {
    switch decision {
    case .skip:
        return nil
    case .finishWithoutSync:
        await finish()
        return nil
    case .sync(let jws):
        return try? await syncThenFinish(jws: jws, sync: sync, finish: finish)
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
            try await tracedSupabase("iap.fetch_products") {
                try await withThrowingTaskGroup(of: [Product].self) { group in
                    group.addTask {
                        try await Product.products(for: LatergramProduct.all)
                    }
                    group.addTask {
                        try await Task.sleep(for: purchaseNetworkTimeout)
                        throw PurchaseError.timeout
                    }
                    defer { group.cancelAll() }
                    guard let products = try await group.next() else {
                        throw PurchaseError.timeout
                    }
                    // StoreKit 斷網真機可能不 throw 直接回 []，視為失敗讓 UI 顯示重試
                    guard !products.isEmpty else { throw PurchaseError.unknown }
                    return products.sorted { $0.price < $1.price }
                }
            }
        },
        purchase: { product in
            // C3: 帶 appAccountToken，讓 server 端 JWS 驗證能比對「交易確實屬於這位用戶」
            let session = try await supabase.auth.session
            let userID = session.user.id
            let options: Set<Product.PurchaseOption> = [.appAccountToken(userID)]
            // syncPremium 自身已包 iap.sync_entitlement，這層只包 StoreKit purchase + verification，避免雙重 capture
            let (transaction, jws): (Transaction, String) = try await tracedSupabase("iap.purchase") {
                let result = try await product.purchase(options: options)
                switch result {
                case .success(let verification):
                    guard case .verified(let transaction) = verification else {
                        throw PurchaseError.verificationFailed
                    }
                    return (transaction, verification.jwsRepresentation)
                case .userCancelled:
                    throw PurchaseError.userCancelled
                case .pending:
                    throw PurchaseError.pending
                @unknown default:
                    throw PurchaseError.unknown
                }
            }
            // 先 sync 成功再 finish；失敗時 transaction 留著，下次 verifyAndSyncEntitlement 會從 currentEntitlements 撿回重試
            return try await syncThenFinish(
                jws: jws,
                sync: { try await syncPremium(jws: $0) },
                finish: { await transaction.finish() }
            )
        },
        verifyAndSyncEntitlement: {
            // 掃完 currentEntitlements 後交給 reconcileEntitlement 決定 promote 或 demote
            // 訂閱自然過期不會觸發 Transaction.updates，必須靠這裡每次登入/foreground 比對
            try await withThrowingTaskGroup(of: UserProfile?.self) { group in
                group.addTask {
                    let session = try await supabase.auth.session
                    let userID = session.user.id

                    var snapshots: [EntitlementSnapshot] = []
                    for await result in Transaction.currentEntitlements {
                        guard case .verified(let transaction) = result else { continue }
                        snapshots.append(EntitlementSnapshot(
                            productID: transaction.productID,
                            revocationDate: transaction.revocationDate,
                            expirationDate: transaction.expirationDate,
                            appAccountToken: transaction.appAccountToken,
                            jws: result.jwsRepresentation
                        ))
                    }

                    switch reconcileEntitlement(entitlements: snapshots, userID: userID, now: Date()) {
                    case .promote(let jws):
                        return try? await syncPremium(jws: jws)
                    case .demote:
                        return try? await syncPremium(jws: nil)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: purchaseNetworkTimeout)
                    throw PurchaseError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        },
        restorePurchases: {
            // syncPremium 自身已包 iap.sync_entitlement，這層只包 StoreKit AppStore.sync()，避免雙重 capture
            try await tracedSupabase("iap.restore_purchases") {
                try await AppStore.sync()
            }
            let session = try await supabase.auth.session
            let userID = session.user.id

            var snapshots: [EntitlementSnapshot] = []
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                snapshots.append(EntitlementSnapshot(
                    productID: transaction.productID,
                    revocationDate: transaction.revocationDate,
                    expirationDate: transaction.expirationDate,
                    appAccountToken: transaction.appAccountToken,
                    jws: result.jwsRepresentation
                ))
            }

            switch reconcileEntitlement(entitlements: snapshots, userID: userID, now: Date()) {
            case .promote(let jws):
                return try await syncPremium(jws: jws)
            case .demote:
                return nil
            }
        },
        observeTransactionUpdates: {
            AsyncStream { continuation in
                let task = Task {
                    for await result in Transaction.updates {
                        guard case .verified(let transaction) = result else { continue }
                        let userID = (try? await supabase.auth.session)?.user.id
                        let decision = transactionUpdateDecision(
                            productID: transaction.productID,
                            revocationDate: transaction.revocationDate,
                            expirationDate: transaction.expirationDate,
                            appAccountToken: transaction.appAccountToken,
                            userID: userID,
                            now: Date(),
                            jws: result.jwsRepresentation
                        )
                        // 真實 entitlement 狀態交給 verifyAndSyncEntitlement（foreground / 登入時呼叫）統一計算。
                        // 過期 transaction 走 finishWithoutSync — server 會擋 400 expired 形成迴圈；
                        // sandbox 殭屍 transaction（殘留未 finish）也由此清除。
                        let profile = await processTransactionUpdate(
                            decision: decision,
                            sync: { try await syncPremium(jws: $0) },
                            finish: { await transaction.finish() }
                        )
                        if let profile { continuation.yield(profile) }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )

    static let testValue = PurchaseClient(
        fetchProducts: { [] },
        purchase: { _ in UserProfile(displayName: "Test") },
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
    try await tracedSupabase("iap.sync_entitlement") {
        let body = SyncEntitlementBody(jws: jws)
        let row: ProfileRow = try await supabase.functions.invoke(
            "sync-entitlement",
            options: FunctionInvokeOptions(body: body)
        )
        return row.toUserProfile()
    }
}
