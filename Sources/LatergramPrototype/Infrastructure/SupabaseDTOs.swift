import LatergramCore
import Foundation

// MARK: - Message

struct MessageRow: Codable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let body: String
    let style_key: String
    let unlock_at: Date
    let status: String
    let revealed_at: Date?
    let created_at: Date
    let sender: ProfileRow?
    let receiver: ProfileRow?

    func toDomain() -> DelayedMessage {
        DelayedMessage(
            id: id,
            senderID: sender_id,
            receiverID: receiver_id,
            senderName: sender?.display_name ?? "",
            receiverName: receiver?.display_name ?? "",
            body: body,
            style: MessageStyle(rawValue: style_key) ?? .classic,
            sentAt: created_at,
            unlockAt: unlock_at,
            status: MessageStatus(rawValue: status) ?? .scheduled,
            revealedAt: revealed_at
        )
    }
}

struct InsertMessageRow: Encodable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let body: String
    let style_key: String
    let unlock_at: Date
    let status: String
}

// MARK: - Profile

struct ProfileRow: Codable {
    let id: UUID
    let display_name: String
    let username: String
    let message_limit: Int?
}

// MARK: - Friendship

struct FriendshipRow: Codable {
    let id: UUID
    let requester_id: UUID
    let addressee_id: UUID
    let status: String
    let requester: ProfileRow?
    let addressee: ProfileRow?

    func toFriend(currentUserID: UUID) -> Friend {
        let isRequester = requester_id == currentUserID
        let profile = isRequester ? addressee : requester
        let friendID = isRequester ? addressee_id : requester_id
        return Friend(
            id: friendID,
            displayName: profile?.display_name ?? "",
            status: FriendshipStatus(rawValue: status) ?? .pending
        )
    }
}

// MARK: - Invite Token

struct InviteTokenRow: Codable {
    let id: UUID
    let token: String
    let inviter_id: UUID
}

struct NewInviteTokenRow: Encodable {
    let inviter_id: UUID
}

// MARK: - Accept Invite RPC

struct AcceptInviteParams: Encodable {
    let invite_code: String
    let accepter_id: UUID
}

struct AcceptInviteResult: Codable {
    let id: UUID
    let display_name: String
}
