import Auth
import Foundation

@discardableResult
func tracedSupabase<T>(
    _ op: String,
    _ work: () async throws -> T
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
        case .userCancelled, .pending:
            return false
        default:
            return true
        }
    }

    return true
}
