import ComposableArchitecture
import LatergramCore
import Foundation
import Realtime

@DependencyClient
struct FriendClient: Sendable {
    var fetchFriends: @Sendable (_ userID: UUID) async throws -> [Friend] = { _ in [] }
    var generateInviteToken: @Sendable (_ userID: UUID) async throws -> String = { _ in "" }
    var acceptInvite: @Sendable (_ code: String, _ userID: UUID) async throws -> Friend
    var revokeInviteToken: @Sendable (_ userID: UUID) async throws -> Void
    var fetchCurrentInviteToken: @Sendable (_ userID: UUID) async throws -> String? = { _ in nil }
    var friendshipStream: @Sendable (_ userID: UUID) -> AsyncStream<Void> = { _ in .finished }
    var removeFriend: @Sendable (_ userID: UUID, _ friendID: UUID) async throws -> Void
}

extension FriendClient: DependencyKey {
    static let liveValue = FriendClient(
        fetchFriends: { userID in
            let rows: [FriendshipRow] = try await supabase
                .from("friendships")
                .select("id, requester_id, addressee_id, status, requester:profiles!requester_id(id, display_name, username), addressee:profiles!addressee_id(id, display_name, username)")
                .or("requester_id.eq.\(userID),addressee_id.eq.\(userID)")
                .eq("status", value: "accepted")
                .execute()
                .value
            return rows.map { $0.toFriend(currentUserID: userID) }
        },
        generateInviteToken: { userID in
            // 先刪除舊的 token
            try await supabase
                .from("invite_tokens")
                .delete()
                .eq("inviter_id", value: userID)
                .execute()

            // 建新 token
            let row: InviteTokenRow = try await supabase
                .from("invite_tokens")
                .insert(NewInviteTokenRow(inviter_id: userID))
                .select()
                .single()
                .execute()
                .value
            return row.token
        },
        acceptInvite: { code, userID in
            do {
                let result: AcceptInviteResult = try await supabase
                    .rpc("accept_invite", params: AcceptInviteParams(invite_code: code, accepter_id: userID))
                    .execute()
                    .value
                return Friend(id: result.id, displayName: result.display_name, status: .accepted)
            } catch {
                let msg = error.localizedDescription
                if msg.contains("already_friends") { throw InviteError.alreadyFriends }
                if msg.contains("invalid_or_revoked") { throw InviteError.invalidOrRevoked }
                if msg.contains("self_invite") { throw InviteError.selfInvite }
                throw error
            }
        },
        revokeInviteToken: { userID in
            try await supabase
                .from("invite_tokens")
                .delete()
                .eq("inviter_id", value: userID)
                .execute()
        },
        fetchCurrentInviteToken: { userID in
            let rows: [InviteTokenRow] = try await supabase
                .from("invite_tokens")
                .select()
                .eq("inviter_id", value: userID)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first?.token
        },
        friendshipStream: { userID in
            AsyncStream { continuation in
                Task {
                    let channel = await supabase.channel("friendships-\(userID)")
                    let insertions = await channel.postgresChange(
                        InsertAction.self,
                        schema: "public",
                        table: "friendships"
                    )
                    let deletions = await channel.postgresChange(
                        DeleteAction.self,
                        schema: "public",
                        table: "friendships"
                    )
                    await channel.subscribe()
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await _ in insertions { continuation.yield(()) }
                        }
                        group.addTask {
                            for await _ in deletions { continuation.yield(()) }
                        }
                    }
                    continuation.finish()
                }
            }
        },
        removeFriend: { userID, friendID in
            try await supabase
                .from("friendships")
                .delete()
                .eq("requester_id", value: userID)
                .eq("addressee_id", value: friendID)
                .execute()
            try await supabase
                .from("friendships")
                .delete()
                .eq("requester_id", value: friendID)
                .eq("addressee_id", value: userID)
                .execute()
        }
    )

    static let previewValue = FriendClient(
        fetchFriends: { _ in SampleData.friends() },
        generateInviteToken: { _ in "PREVIEW1" },
        acceptInvite: { _, _ in Friend(displayName: "NewFriend", status: .accepted) },
        revokeInviteToken: { _ in },
        fetchCurrentInviteToken: { _ in nil },
        friendshipStream: { _ in .finished },
        removeFriend: { _, _ in }
    )
}

extension DependencyValues {
    var friendClient: FriendClient {
        get { self[FriendClient.self] }
        set { self[FriendClient.self] = newValue }
    }
}

enum InviteError: Error, LocalizedError {
    case invalidOrRevoked
    case alreadyFriends
    case selfInvite

    var errorDescription: String? {
        switch self {
        case .invalidOrRevoked: "邀請碼無效或已失效"
        case .alreadyFriends: "你們已經是好友"
        case .selfInvite: "不可邀請自己"
        }
    }
}
