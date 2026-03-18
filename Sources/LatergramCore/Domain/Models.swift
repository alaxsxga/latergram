import Foundation

public enum FriendshipStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case blocked
}

public enum MessageStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case classic
    case warm
    case cool
    case heart

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .classic: "Classic"
        case .warm: "Warm"
        case .cool: "Cool"
        case .heart: "Heart"
        }
    }
}

public enum MessageStatus: String, Codable, Sendable {
    case scheduled
    case readyToReveal = "ready_to_reveal"
    case revealed
}

public struct Friend: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var status: FriendshipStatus

    public init(id: UUID = UUID(), displayName: String, status: FriendshipStatus) {
        self.id = id
        self.displayName = displayName
        self.status = status
    }
}

public struct DelayedMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let senderID: UUID
    public let receiverID: UUID
    public var senderName: String
    public var body: String
    public var style: MessageStyle
    public var sentAt: Date
    public var unlockAt: Date
    public var status: MessageStatus
    public var revealedAt: Date?

    public init(
        id: UUID = UUID(),
        senderID: UUID,
        receiverID: UUID,
        senderName: String,
        body: String,
        style: MessageStyle,
        sentAt: Date = Date(),
        unlockAt: Date,
        status: MessageStatus = .scheduled,
        revealedAt: Date? = nil
    ) {
        self.id = id
        self.senderID = senderID
        self.receiverID = receiverID
        self.senderName = senderName
        self.body = body
        self.style = style
        self.sentAt = sentAt
        self.unlockAt = unlockAt
        self.status = status
        self.revealedAt = revealedAt
    }
}

public struct UserProfile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var username: String

    public init(id: UUID = UUID(), displayName: String, username: String) {
        self.id = id
        self.displayName = displayName
        self.username = username
    }
}
