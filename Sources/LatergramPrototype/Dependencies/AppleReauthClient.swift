import ComposableArchitecture
import Foundation
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

// 刪帳號時重新做一次 Sign in with Apple，只為了取得一組新的 authorizationCode。
// native signInWithIdToken 從不換 refresh token，所以撤銷授權（5.1.1(v)）需要當下重取一組，
// 交給 delete-account Edge Function 去 Apple 換 token 再 revoke。
@DependencyClient
struct AppleReauthClient: Sendable {
    /// 觸發系統面板重新驗證，回傳新的 authorizationCode。
    /// 使用者取消面板 → 丟 `CancellationError`（呼叫端據此靜默中止刪除）。
    var authorizationCode: @Sendable () async throws -> String
}

extension AppleReauthClient: DependencyKey {
    static let liveValue = AppleReauthClient(
        authorizationCode: {
            #if os(iOS)
            return try await AppleReauthCoordinator.run()
            #else
            throw AppleReauthError.unsupported
            #endif
        }
    )

    static let testValue = AppleReauthClient(authorizationCode: { "" })
}

extension DependencyValues {
    var appleReauthClient: AppleReauthClient {
        get { self[AppleReauthClient.self] }
        set { self[AppleReauthClient.self] = newValue }
    }
}

enum AppleReauthError: Error { case unsupported, missingCode }

#if os(iOS)
// ASAuthorizationController 只弱參考 delegate，故需外部強留存到 callback 回來為止。
@MainActor
private final class AppleReauthCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<String, Error>?
    private static var retained: AppleReauthCoordinator?

    static func run() async throws -> String {
        let coordinator = AppleReauthCoordinator()
        retained = coordinator
        defer { retained = nil }
        return try await coordinator.start()
    }

    private func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            // 只要拿 authorizationCode；不需要任何 scope。
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8)
        else {
            continuation?.resume(throwing: AppleReauthError.missingCode)
            return
        }
        continuation?.resume(returning: code)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { continuation = nil }
        // 使用者自己取消（滑掉面板）→ 當作取消，讓上層靜默中止。
        if (error as? ASAuthorizationError)?.code == .canceled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: error)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        return windowScene?.keyWindow ?? ASPresentationAnchor()
    }
}
#endif
