import ComposableArchitecture
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 使用者送出的回饋。content/category/contactEmail 是使用者填的；
/// app/os/device/locale 等環境欄位由 client 在送出時自動補上。
struct FeedbackSubmission: Sendable, Equatable {
    var userID: UUID
    var category: String?
    var content: String
    var contactEmail: String?
    var isPremium: Bool
}

@DependencyClient
struct FeedbackClient: Sendable {
    var submit: @Sendable (_ submission: FeedbackSubmission) async throws -> Void
    /// 預填用：目前登入帳號的 email（拿不到回 nil）。
    var currentEmail: @Sendable () async -> String? = { nil }
}

extension FeedbackClient: DependencyKey {
    static let liveValue = FeedbackClient(
        submit: { submission in
            try await tracedSupabase("feedback.submit") {
                let trimmedEmail = submission.contactEmail?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let row = InsertFeedbackRow(
                    user_id: submission.userID,
                    category: submission.category,
                    content: submission.content,
                    contact_email: (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil,
                    app_version: appVersion(),
                    os_version: osVersion(),
                    device_model: deviceModel(),
                    is_premium: submission.isPremium,
                    locale: Locale.current.identifier
                )
                _ = try await supabase.from("feedback").insert(row).execute()
            }
        },
        currentEmail: {
            let session = try? await supabase.auth.session
            return session?.user.email
        }
    )

    static let previewValue = FeedbackClient(
        submit: { _ in },
        currentEmail: { "you@example.com" }
    )

    static let testValue = FeedbackClient(
        submit: { _ in },
        currentEmail: { nil }
    )
}

extension DependencyValues {
    var feedbackClient: FeedbackClient {
        get { self[FeedbackClient.self] }
        set { self[FeedbackClient.self] = newValue }
    }
}

// MARK: - 環境欄位

private func appVersion() -> String? {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String
    let build = info?["CFBundleVersion"] as? String
    guard let version else { return build }
    return build.map { "\(version)+\($0)" } ?? version
}

private func osVersion() -> String? {
    #if canImport(UIKit)
    return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    #else
    return nil
    #endif
}

private func deviceModel() -> String? {
    #if canImport(UIKit)
    // UIDevice.current.model 只回 "iPhone"；用 uname 取得 "iPhone15,2" 這種型號碼。
    var sysinfo = utsname()
    uname(&sysinfo)
    let identifier = Mirror(reflecting: sysinfo.machine).children.reduce(into: "") { result, element in
        guard let value = element.value as? Int8, value != 0 else { return }
        result.append(Character(UnicodeScalar(UInt8(value))))
    }
    return identifier.isEmpty ? UIDevice.current.model : identifier
    #else
    return nil
    #endif
}
