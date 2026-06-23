#if os(iOS)
import Auth
import Foundation

// Returns true for errors caused by user input — these are shown as UI messages
// and should not be reported to Sentry as unexpected errors.
func isUserInputAuthError(_ error: Error) -> Bool {
    guard let authError = error as? AuthError else { return false }
    switch authError.errorCode {
    case .invalidCredentials, .userNotFound,
         .emailNotConfirmed,
         .validationFailed,
         .weakPassword,
         .emailExists, .userAlreadyExists:
        return true
    default:
        return false
    }
}

// True when GoTrue rejects the new password for being identical to the current one
// (error_code "same_password"). In the recovery flow the user is already authenticated,
// so re-entering their existing password is harmless — callers treat this as success.
func isSamePasswordError(_ error: Error) -> Bool {
    (error as? AuthError)?.errorCode == .samePassword
}

func localizedAuthErrorMessage(_ error: Error) -> String {
    if let authError = error as? AuthError {
        switch authError.errorCode {
        case .invalidCredentials, .userNotFound:
            return LS("auth.error.invalid_credentials")
        case .emailNotConfirmed:
            return LS("auth.error.email_not_confirmed")
        case .overRequestRateLimit, .overEmailSendRateLimit:
            return LS("auth.error.rate_limit")
        case .validationFailed:
            return LS("auth.error.invalid_email_format")
        case .weakPassword:
            return LS("auth.error.password_too_short")
        case .emailExists, .userAlreadyExists:
            return LS("auth.error.email_already_registered")
        default:
            break
        }
    }
    let nsError = error as NSError
    if nsError.domain == "AuthClient", nsError.code == 409 {
        return LS("auth.error.email_already_registered")
    }
    if error is URLError {
        return LS("auth.error.network")
    }
    return LS("auth.error.generic")
}
#endif
