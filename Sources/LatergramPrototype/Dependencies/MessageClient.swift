import ComposableArchitecture
import LatergramCore
import Foundation

@DependencyClient
struct MessageClient: Sendable {
    var fetchCountdownFeed: @Sendable (_ userID: UUID) async throws -> [DelayedMessage] = { _ in [] }
    var fetchThread: @Sendable (_ userID: UUID, _ friendID: UUID) async throws -> [DelayedMessage] = { _, _ in [] }
    var send: @Sendable (_ message: DelayedMessage) async throws -> Void
    var reveal: @Sendable (_ messageID: UUID, _ now: Date) async throws -> Bool = { _, _ in false }
    var delete: @Sendable (_ messageID: UUID, _ userID: UUID) async throws -> Void
}

extension MessageClient: DependencyKey {
    static let liveValue = MessageClient(
        fetchCountdownFeed: { userID in
            // Fetch newest 300 messages, then reverse to ascending order for display
            let rows: [MessageRow] = try await supabase
                .from("messages")
                .select("id, sender_id, receiver_id, body, style_key, unlock_at, status, revealed_at, created_at, sender:profiles!sender_id(id, display_name, username), receiver:profiles!receiver_id(id, display_name, username)")
                .or("sender_id.eq.\(userID),receiver_id.eq.\(userID)")
                .order("unlock_at", ascending: false)
                .limit(300)
                .execute()
                .value
            return rows.reversed().map { $0.toDomain() }
        },
        fetchThread: { userID, friendID in
            // Fetch newest 300 messages, then reverse to ascending order for display
            let rows: [MessageRow] = try await supabase
                .from("messages")
                .select("id, sender_id, receiver_id, body, style_key, unlock_at, status, revealed_at, created_at, sender:profiles!sender_id(id, display_name, username), receiver:profiles!receiver_id(id, display_name, username)")
                .or("and(sender_id.eq.\(userID),receiver_id.eq.\(friendID)),and(sender_id.eq.\(friendID),receiver_id.eq.\(userID))")
                .order("created_at", ascending: false)
                .limit(300)
                .execute()
                .value
            return rows.reversed().map { $0.toDomain() }
        },
        send: { message in
            let row = InsertMessageRow(
                id: message.id,
                sender_id: message.senderID,
                receiver_id: message.receiverID,
                body: message.body,
                style_key: message.style.rawValue,
                unlock_at: message.unlockAt,
                status: message.status.rawValue
            )
            try await supabase
                .from("messages")
                .insert(row)
                .execute()
        },
        reveal: { messageID, now in
            struct UpdateStatus: Encodable {
                let status: String
                let revealed_at: Date
            }
            struct RowID: Decodable { let id: UUID }
            let updated: [RowID] = try await supabase
                .from("messages")
                .update(UpdateStatus(status: "revealed", revealed_at: now))
                .eq("id", value: messageID)
                .select("id")
                .execute()
                .value
            guard !updated.isEmpty else {
                struct RevealBlockedError: Error {}
                throw RevealBlockedError()
            }
            return true
        },
        delete: { messageID, userID in
            try await supabase
                .from("message_deletions")
                .insert(InsertDeletionRow(user_id: userID, message_id: messageID))
                .execute()
        }
    )

    static let previewValue: MessageClient = {
        let me = UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Ed",
            username: "ed"
        )
        let friends = SampleData.friends()
        let messages = SampleData.messages(me: me, friends: friends)
        return MessageClient(
            fetchCountdownFeed: { _ in messages },
            fetchThread: { userID, friendID in
                messages.filter {
                    ($0.senderID == userID && $0.receiverID == friendID)
                    || ($0.senderID == friendID && $0.receiverID == userID)
                }
            },
            send: { _ in },
            reveal: { _, _ in true },
            delete: { _, _ in }
        )
    }()
}

extension DependencyValues {
    var messageClient: MessageClient {
        get { self[MessageClient.self] }
        set { self[MessageClient.self] = newValue }
    }
}
