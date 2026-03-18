import Foundation

public struct NotificationRebuildPolicy: Sendable {
    public let cap: Int
    public let throttleSeconds: TimeInterval

    public init(cap: Int = 64, throttleSeconds: TimeInterval = 30) {
        self.cap = cap
        self.throttleSeconds = throttleSeconds
    }

    public func shouldRebuild(lastRebuildAt: Date?, now: Date) -> Bool {
        guard let lastRebuildAt else { return true }
        return now.timeIntervalSince(lastRebuildAt) >= throttleSeconds
    }

    public func selectMessagesForScheduling(_ messages: [DelayedMessage], now: Date) -> [DelayedMessage] {
        messages
            .filter { $0.status != .revealed && $0.unlockAt > now }
            .sorted { $0.unlockAt < $1.unlockAt }
            .prefix(cap)
            .map { $0 }
    }
}
