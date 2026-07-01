#if os(iOS)
import Foundation
import MachO
import Sentry
import UIKit

public enum SentryBootstrap {
    public static func start() {
        SentrySDK.start { options in
            options.dsn = Secrets.sentryDSN
            options.environment = currentEnvironment()
            options.releaseName = currentRelease()
            options.enableAutoSessionTracking = true
            options.sendDefaultPii = false
            options.tracesSampleRate = 0.1
            options.attachStacktrace = true
            options.beforeSend = sanitize(event:)
            options.beforeBreadcrumb = sanitize(breadcrumb:)
            #if DEBUG
            options.debug = true
            options.diagnosticLevel = .warning
            // 接線 Run 時拔線 / 從 Xcode 停止會讓上次 session 被判為非正常結束，
            // Sentry 下次啟動誤報成 watchdog termination。dev 不追，真 OOM 仍有 memory warning breadcrumb。
            options.enableWatchdogTerminationTracking = false
            #endif
        }
        startMemoryWarningObserver()
    }

    // Logs memory footprint when iOS fires a memory warning so that watchdog
    // termination events include breadcrumbs showing memory state before the kill.
    private static func startMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            let mb = memoryFootprintMB()
            var data: [String: String] = ["level": "warning"]
            if let mb {
                data["resident_mb"] = "\(mb)"
                SentrySDK.configureScope { scope in
                    scope.setExtra(value: mb, key: "memory_warning_resident_mb")
                }
            }
            addBreadcrumb(
                category: "memory",
                message: mb.map { "Memory warning — \($0) MB resident" } ?? "Memory warning",
                level: .warning,
                data: data
            )
        }
    }

    private static func memoryFootprintMB() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size / 1_048_576)
    }

    // displayName is user-chosen and treated as low-PII; email/phone never go in.
    public static func identify(userID: UUID, displayName: String) {
        let user = User()
        user.userId = userID.uuidString
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            user.username = trimmed
        }
        SentrySDK.setUser(user)
    }

    // Clears user + scope so events from the next session don't inherit the
    // previous user's breadcrumbs (CLAUDE.md rule 1).
    public static func clearUser() {
        SentrySDK.setUser(nil)
        SentrySDK.configureScope { scope in
            scope.clear()
        }
    }

    public static func captureBackend(_ error: Error, op: String) {
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: op, key: "supabase.op")
        }
    }

    public static func addBreadcrumb(
        category: String,
        message: String,
        level: SentryLevel = .info,
        data: [String: String]? = nil
    ) {
        let crumb = Breadcrumb()
        crumb.category = category
        crumb.message = message
        crumb.level = level
        if let data {
            crumb.data = data
        }
        SentrySDK.addBreadcrumb(crumb)
    }

    private static func currentEnvironment() -> String {
        #if DEBUG
        return "dev"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return "production"
        #endif
    }

    private static func currentRelease() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "latergram-ios@\(version)+\(build)"
    }

    private static func sanitize(event: Event) -> Event? {
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: redact(formatted))
        }
        event.exceptions?.forEach { exception in
            exception.value = redact(exception.value)
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap(sanitize(breadcrumb:))
        return event
    }

    private static func sanitize(breadcrumb: Breadcrumb) -> Breadcrumb? {
        if let message = breadcrumb.message {
            breadcrumb.message = redact(message)
        }
        if var data = breadcrumb.data {
            if breadcrumb.category == "http", let url = data["url"] as? String {
                data["url"] = redactURL(url)
            }
            breadcrumb.data = data.mapValues { value in
                (value as? String).map(redact) ?? value
            }
        }
        return breadcrumb
    }

    // Supabase access/refresh tokens 與 App Store JWS 都是 JWT 形狀（eyJ...）
    private static let jwtRegex = try? NSRegularExpression(
        pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
    )
    private static let bearerRegex = try? NSRegularExpression(
        pattern: #"(?i)Bearer\s+[A-Za-z0-9._-]+"#
    )

    private static func redact(_ string: String) -> String {
        var result = string
        if let regex = jwtRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[REDACTED_JWT]"
            )
        }
        if let regex = bearerRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[REDACTED_BEARER]"
            )
        }
        return result
    }

    private static func redactURL(_ string: String) -> String {
        guard var components = URLComponents(string: string) else { return redact(string) }
        if components.query != nil {
            components.query = "[REDACTED]"
        }
        return components.string ?? redact(string)
    }
}
#endif
