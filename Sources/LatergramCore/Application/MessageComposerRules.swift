import Foundation

public enum ComposeValidationError: Error, Equatable, Sendable {
    case emptyBody
    case tooLong(max: Int)
    case unlockTooSoon
    case unlockTooLate
}

public struct MessageComposerRules: Sendable {
    public let minDelaySeconds: TimeInterval
    public let maxDelaySeconds: TimeInterval
    public let maxLength: Int

    public init(
        minDelaySeconds: TimeInterval = 60,
        maxDelaySeconds: TimeInterval = 7 * 24 * 3600,
        maxLength: Int = 1000
    ) {
        self.minDelaySeconds = minDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.maxLength = maxLength
    }

    public func validate(
        body: String,
        unlockAt: Date,
        now: Date
    ) -> ComposeValidationError? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyBody }
        if trimmed.count > maxLength { return .tooLong(max: maxLength) }

        let interval = unlockAt.timeIntervalSince(now)
        if interval < minDelaySeconds { return .unlockTooSoon }
        if interval > maxDelaySeconds { return .unlockTooLate }

        return nil
    }
}
