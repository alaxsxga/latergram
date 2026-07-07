import ComposableArchitecture
import Foundation
#if os(iOS)
import StoreKit
import UIKit
#endif

/// Requests the native App Store rating prompt after the user's first successful reveal.
/// The gating flag is device-level (tied to the App Store account, not the signed-in user),
/// so it intentionally survives logout and is not part of the logout clean-slate flow.
///
/// Whether the prompt actually appears is up to the system: development builds always show it,
/// TestFlight builds never do, and App Store builds are capped at 3 displays per year.
@DependencyClient
struct AppReviewClient: Sendable {
    /// `true` once the first-reveal review prompt has been requested on this device.
    var hasRequestedFirstRevealReview: @Sendable () -> Bool = { true }
    var markFirstRevealReviewRequested: @Sendable () -> Void = {}
    var requestReview: @Sendable () async -> Void = {}
}

extension AppReviewClient: DependencyKey {
    private static let requestedKey = "appReview.firstRevealReviewRequested"

    static let liveValue = AppReviewClient(
        hasRequestedFirstRevealReview: {
            UserDefaults.standard.bool(forKey: requestedKey)
        },
        markFirstRevealReviewRequested: {
            UserDefaults.standard.set(true, forKey: requestedKey)
        },
        requestReview: {
            #if os(iOS)
            await MainActor.run {
                guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                else { return }
                AppStore.requestReview(in: scene)
            }
            #endif
        }
    )

    // Inert test value: "already requested" means existing reducer tests never
    // enter the review-request path unless they opt in by overriding.
    static let testValue = AppReviewClient(
        hasRequestedFirstRevealReview: { true },
        markFirstRevealReviewRequested: {},
        requestReview: {}
    )
}

extension DependencyValues {
    var appReviewClient: AppReviewClient {
        get { self[AppReviewClient.self] }
        set { self[AppReviewClient.self] = newValue }
    }
}
