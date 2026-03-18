import ComposableArchitecture
import LatergramCore
import Foundation
import UserNotifications

// MARK: - Delegate (bridges UNUserNotificationCenterDelegate → AsyncStream)

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<UUID>.Continuation
    let stream: AsyncStream<UUID>

    override init() {
        let (stream, continuation) = AsyncStream<UUID>.makeStream()
        self.stream = stream
        self.continuation = continuation
        super.init()
    }

    // Called when user taps a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let idString = response.notification.request.content.userInfo["messageID"] as? String,
           let id = UUID(uuidString: idString) {
            continuation.yield(id)
        }
        completionHandler()
    }

    // Show banner + sound even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Client

/// Local notification scheduling + tap event stream.
@DependencyClient
struct NotificationClient: Sendable {
    var requestPermission: @Sendable () async -> Bool = { false }
    var scheduleMessages: @Sendable (_ messages: [DelayedMessage]) async -> Void = { _ in }
    var cancelAll: @Sendable () async -> Void = {}
    /// Emits a messageID each time the user taps a Delaygram notification.
    var notificationTapStream: @Sendable () -> AsyncStream<UUID> = { .finished }
}

// MARK: - Sendable wrapper for UNUserNotificationCenter (Swift 6)

/// UNUserNotificationCenter is not Sendable, but we access it only via
/// async methods that are internally main-actor-safe on Apple platforms.
private struct SendableCenter: @unchecked Sendable {
    let value: UNUserNotificationCenter
}

// MARK: - Live

extension NotificationClient: DependencyKey {
    static let liveValue: NotificationClient = {
        let box = SendableCenter(value: UNUserNotificationCenter.current())
        let delegate = NotificationDelegate()
        box.value.delegate = delegate

        return NotificationClient(
            requestPermission: {
                do {
                    return try await box.value.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    return false
                }
            },

            scheduleMessages: { messages in
                // Remove previously scheduled Delaygram notifications
                let pending = await box.value.pendingNotificationRequests()
                let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix("dg-") }
                box.value.removePendingNotificationRequests(withIdentifiers: oldIDs)

                // Schedule fresh ones
                for message in messages {
                    let content = UNMutableNotificationContent()
                    content.title = "來自 \(message.senderName) 的訊息可以開啟了"
                    content.body = "點擊查看"          // 不含未 reveal 的內文
                    content.sound = .default
                    content.userInfo = [
                        "messageID": message.id.uuidString,
                        "senderID": message.senderID.uuidString
                    ]

                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second],
                        from: message.unlockAt
                    )
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: false
                    )
                    let request = UNNotificationRequest(
                        identifier: "dg-\(message.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    try? await box.value.add(request)
                }
            },

            cancelAll: {
                let pending = await box.value.pendingNotificationRequests()
                let ids = pending.map(\.identifier).filter { $0.hasPrefix("dg-") }
                box.value.removePendingNotificationRequests(withIdentifiers: ids)
            },

            notificationTapStream: { delegate.stream }
        )
    }()

    static let testValue = NotificationClient(
        requestPermission: { true },
        scheduleMessages: { _ in },
        cancelAll: {},
        notificationTapStream: { .finished }
    )
}

extension DependencyValues {
    var notificationClient: NotificationClient {
        get { self[NotificationClient.self] }
        set { self[NotificationClient.self] = newValue }
    }
}
