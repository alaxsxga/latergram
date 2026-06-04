import XCTest
import LatergramCore
@testable import LatergramPrototype

final class PurchaseClientTests: XCTestCase {

    private let userID = UUID()
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let validProductID = LatergramProduct.premiumMonthly

    // MARK: - reconcileEntitlement

    func test_reconcile_noEntitlements_returnsDemote() {
        let decision = reconcileEntitlement(entitlements: [], userID: userID, now: now)
        XCTAssertEqual(decision, .demote)
    }

    func test_reconcile_validActiveEntitlement_returnsPromote() {
        let ent = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            jws: "valid-jws"
        )
        let decision = reconcileEntitlement(entitlements: [ent], userID: userID, now: now)
        XCTAssertEqual(decision, .promote(jws: "valid-jws"))
    }

    func test_reconcile_revokedEntitlement_returnsDemote() {
        let ent = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: now.addingTimeInterval(-60),
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            jws: "jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [ent], userID: userID, now: now), .demote)
    }

    func test_reconcile_expiredEntitlement_returnsDemote() {
        let ent = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(-1),
            appAccountToken: userID,
            jws: "jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [ent], userID: userID, now: now), .demote)
    }

    func test_reconcile_tokenMismatch_returnsDemote() {
        let otherUser = UUID()
        let ent = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: otherUser,
            jws: "jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [ent], userID: userID, now: now), .demote)
    }

    func test_reconcile_legacyEntitlementWithoutToken_returnsPromote() {
        // 舊訂閱 / family sharing 可能沒有 appAccountToken — 暫時放行
        let ent = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: nil,
            jws: "legacy-jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [ent], userID: userID, now: now), .promote(jws: "legacy-jws"))
    }

    func test_reconcile_unrelatedProductID_returnsDemote() {
        let ent = EntitlementSnapshot(
            productID: "com.other.product",
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            jws: "jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [ent], userID: userID, now: now), .demote)
    }

    func test_reconcile_picksFirstValidWhenMultiple() {
        let revoked = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: now,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            jws: "revoked-jws"
        )
        let valid = EntitlementSnapshot(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            jws: "good-jws"
        )
        XCTAssertEqual(reconcileEntitlement(entitlements: [revoked, valid], userID: userID, now: now), .promote(jws: "good-jws"))
    }

    // MARK: - transactionUpdateDecision

    func test_decision_renewalActive_returnsSync() {
        let d = transactionUpdateDecision(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            userID: userID,
            now: now,
            jws: "new-jws"
        )
        XCTAssertEqual(d, .sync(jws: "new-jws"))
    }

    func test_decision_revoked_returnsSyncNil() {
        let d = transactionUpdateDecision(
            productID: validProductID,
            revocationDate: now.addingTimeInterval(-60),
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            userID: userID,
            now: now,
            jws: "jws"
        )
        XCTAssertEqual(d, .sync(jws: nil))
    }

    func test_decision_loggedOut_returnsSkip() {
        let d = transactionUpdateDecision(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            userID: nil,
            now: now,
            jws: "jws"
        )
        XCTAssertEqual(d, .skip)
    }

    func test_decision_tokenMismatch_returnsSkip() {
        let d = transactionUpdateDecision(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: UUID(),
            userID: userID,
            now: now,
            jws: "jws"
        )
        XCTAssertEqual(d, .skip)
    }

    func test_decision_expired_returnsFinishWithoutSync() {
        let d = transactionUpdateDecision(
            productID: validProductID,
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(-1),
            appAccountToken: userID,
            userID: userID,
            now: now,
            jws: "jws"
        )
        XCTAssertEqual(d, .finishWithoutSync)
    }

    func test_decision_unrelatedProduct_returnsFinishWithoutSync() {
        let d = transactionUpdateDecision(
            productID: "com.other.product",
            revocationDate: nil,
            expirationDate: now.addingTimeInterval(3600),
            appAccountToken: userID,
            userID: userID,
            now: now,
            jws: "jws"
        )
        XCTAssertEqual(d, .finishWithoutSync)
    }

    // MARK: - processTransactionUpdate

    func test_process_skip_doesNotSyncOrFinish() async {
        let finishTracker = CallTracker()
        let syncTracker = CallTracker()
        let profile = await processTransactionUpdate(
            decision: .skip,
            sync: { _ in
                await syncTracker.record()
                return UserProfile(displayName: "x")
            },
            finish: { await finishTracker.record() }
        )
        XCTAssertNil(profile)
        let finishCount = await finishTracker.count
        let syncCount = await syncTracker.count
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(syncCount, 0)
    }

    func test_process_finishWithoutSync_finishesButDoesNotSync() async {
        let finishTracker = CallTracker()
        let syncTracker = CallTracker()
        let profile = await processTransactionUpdate(
            decision: .finishWithoutSync,
            sync: { _ in
                await syncTracker.record()
                return UserProfile(displayName: "x")
            },
            finish: { await finishTracker.record() }
        )
        XCTAssertNil(profile)
        let finishCount = await finishTracker.count
        let syncCount = await syncTracker.count
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(syncCount, 0)
    }

    func test_process_syncSuccess_syncsThenFinishesAndReturnsProfile() async {
        let finishTracker = CallTracker()
        let expected = UserProfile(id: UUID(), displayName: "Alice", isPremium: true)
        let result = await processTransactionUpdate(
            decision: .sync(jws: "jws-abc"),
            sync: { jws in
                XCTAssertEqual(jws, "jws-abc")
                return expected
            },
            finish: { await finishTracker.record() }
        )
        XCTAssertEqual(result?.id, expected.id)
        let finishCount = await finishTracker.count
        XCTAssertEqual(finishCount, 1)
    }

    func test_process_syncFailure_doesNotFinishAndReturnsNil() async {
        let finishTracker = CallTracker()
        let result = await processTransactionUpdate(
            decision: .sync(jws: "jws"),
            sync: { _ in throw PurchaseError.verificationFailed },
            finish: { await finishTracker.record() }
        )
        XCTAssertNil(result)
        let finishCount = await finishTracker.count
        XCTAssertEqual(finishCount, 0, "sync 失敗時 transaction.finish() 不可被呼叫")
    }

    // MARK: - syncThenFinish（purchase 路徑）

    func test_syncThenFinish_success_finishesAndReturnsProfile() async throws {
        let finishTracker = CallTracker()
        let expected = UserProfile(id: UUID(), displayName: "Bob", isPremium: true)
        let result = try await syncThenFinish(
            jws: "jws",
            sync: { _ in expected },
            finish: { await finishTracker.record() }
        )
        XCTAssertEqual(result.id, expected.id)
        let finishCount = await finishTracker.count
        XCTAssertEqual(finishCount, 1)
    }

    func test_syncThenFinish_syncFailure_throwsAndDoesNotFinish() async {
        let finishTracker = CallTracker()
        do {
            _ = try await syncThenFinish(
                jws: "jws",
                sync: { _ in throw PurchaseError.verificationFailed },
                finish: { await finishTracker.record() }
            )
            XCTFail("應該 throw")
        } catch {
            XCTAssertEqual(error as? PurchaseError, .verificationFailed)
        }
        let finishCount = await finishTracker.count
        XCTAssertEqual(finishCount, 0, "purchase sync 失敗時不可 finish，留 transaction 給下次 verify 撿回")
    }
}

// MARK: - Helpers

private actor CallTracker {
    private(set) var count = 0
    func record() { count += 1 }
}
