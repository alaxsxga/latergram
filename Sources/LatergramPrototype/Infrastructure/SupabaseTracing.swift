import Auth
import Foundation
import StoreKit

@discardableResult
func tracedSupabase<T: Sendable>(
    _ op: String,
    _ work: @Sendable () async throws -> T
) async throws -> T {
    do {
        return try await work()
    } catch {
        if shouldCaptureForSentry(error) {
            #if os(iOS)
            SentryBootstrap.captureBackend(error, op: op)
            #endif
        }
        throw error
    }
}

private func shouldCaptureForSentry(_ error: Error) -> Bool {
    if error is CancellationError { return false }

    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .cancelled:
            return false
        default:
            return true
        }
    }

    if let authError = error as? AuthError {
        if case let .api(_, _, _, response) = authError {
            return response.statusCode >= 500
        }
        return true
    }

    if error is InviteError { return false }

    if let purchaseError = error as? PurchaseError {
        switch purchaseError {
        // timeout 跟 URLError.timedOut 同類別網路訊號，一致 SKIP
        case .userCancelled, .pending, .timeout:
            return false
        default:
            return true
        }
    }

    // restore（AppStore.sync）不經 purchase 那段 switch 轉換，會丟原生 StoreKitError，
    // 需在此比照 PurchaseError 過濾掉使用者取消與網路噪音，避免誤報上 Sentry。
    if let storeKitError = error as? StoreKitError {
        switch storeKitError {
        case .userCancelled, .networkError:
            return false
        default:
            return true
        }
    }

    return true
}
