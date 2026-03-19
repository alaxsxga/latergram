import ComposableArchitecture
import LatergramCore
import Foundation

enum AcceptInviteFailure: Equatable {
    case alreadyFriends
    case other(String)

    var message: String {
        switch self {
        case .alreadyFriends: "你們已經是好友"
        case .other(let msg): msg
        }
    }
}

@Reducer
struct FriendsFeature {
    @ObservableState
    struct State: Equatable {
        var me: UserProfile = UserProfile(displayName: "", username: "")
        var friends: IdentifiedArrayOf<Friend> = []
        var generatedInviteCode = ""
        var pastedInviteCode = ""
        var isLoading = false
        var isSharingInvite = false
        var inviteShareMessage = ""
        var isConfirmingLogout = false
        var banner: String?
        var lastFetchedAt: Date? = nil
        var friendPendingDeletion: Friend? = nil
        var showDeepLinkInviteAlert = false
        var inviteAcceptError: AcceptInviteFailure? = nil
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case generateInviteCodeTapped
        case shareInviteCodeTapped
        case shareSheetDismissed
        case revokeInviteCodeTapped
        case acceptInviteCodeTapped
        case logoutConfirmTapped
        case logoutCancelled
        case logoutTapped
        case inviteCodeGenerated(String)
        case existingInviteCodeLoaded(String)
        case friendsLoaded([Friend])
        case remoteFriendsLoaded([Friend])
        case loadFailed(String)
        case remoteFetchFailed(String)
        case inviteAccepted(Friend)
        case inviteAcceptFailed(AcceptInviteFailure)
        case logoutSucceeded
        case foregroundRefresh
        case realtimeChangeDetected
        case removeFriendSwiped(Friend)
        case removeFriendConfirmed
        case removeFriendCancelled
        case removeFriendSucceeded(UUID)
        case removeFriendFailed(String)
        case acceptInviteFromDeepLink(String)
        case deepLinkAlertDismissed
        case inviteAcceptErrorDismissed
    }

    @Dependency(\.friendClient) var friendClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient

    private enum CancelID { case realtimeSubscription }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .binding:
                return .none

            case .onAppear:
                print("[FriendsFeature] onAppear — state.me = \(state.me.username)")
                let cached = friendsCacheClient.load(state.me.id)
                if !cached.isEmpty {
                    state.friends = IdentifiedArray(uniqueElements: cached)
                    state.isLoading = false
                } else {
                    state.isLoading = true
                }

                let fetchEffect: Effect<Action> = state.lastFetchedAt == nil
                    ? .run { [id = state.me.id] send in
                        do {
                            let friends = try await friendClient.fetchFriends(id)
                            await send(.remoteFriendsLoaded(friends))
                        } catch {
                            await send(.remoteFetchFailed(error.localizedDescription))
                        }
                      }
                    : .none

                let realtimeEffect: Effect<Action> = .run { [id = state.me.id] send in
                    for await _ in friendClient.friendshipStream(id) {
                        await send(.realtimeChangeDetected)
                    }
                }
                .cancellable(id: CancelID.realtimeSubscription, cancelInFlight: true)

                let inviteEffect: Effect<Action> = .run { [id = state.me.id] send in
                    do {
                        if let token = try await friendClient.fetchCurrentInviteToken(id) {
                            await send(.existingInviteCodeLoaded(token))
                        }
                    } catch {
                        await send(.loadFailed("邀請碼載入失敗: \(error.localizedDescription)"))
                    }
                }

                return .merge(fetchEffect, realtimeEffect, inviteEffect)

            case .generateInviteCodeTapped:
                return .run { [id = state.me.id] send in
                    do {
                        let token = try await friendClient.generateInviteToken(id)
                        await send(.inviteCodeGenerated(token))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }

            case .acceptInviteFromDeepLink(let code):
                print("[DeepLink] acceptInviteFromDeepLink code=\(code)")
                state.pastedInviteCode = code
                state.showDeepLinkInviteAlert = true
                return .none

            case .deepLinkAlertDismissed:
                state.showDeepLinkInviteAlert = false
                return .none

            case .shareInviteCodeTapped:
                state.inviteShareMessage = "加我的 Delaygram！\ndelaygram://invite?code=\(state.generatedInviteCode)"
                state.isSharingInvite = true
                return .none

            case .shareSheetDismissed:
                state.isSharingInvite = false
                return .none

            case .revokeInviteCodeTapped:
                state.generatedInviteCode = ""
                return .run { [id = state.me.id] _ in
                    try? await friendClient.revokeInviteToken(id)
                }

            case .acceptInviteCodeTapped:
                let code = state.pastedInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[DeepLink] acceptInviteCodeTapped code='\(code)'")
                guard !code.isEmpty else {
                    state.banner = "邀請碼不可為空"
                    return .none
                }
                return .run { [id = state.me.id] send in
                    do {
                        let friend = try await friendClient.acceptInvite(code, id)
                        await send(.inviteAccepted(friend))
                    } catch {
                        let failure: AcceptInviteFailure = (error as? InviteError) == .alreadyFriends
                            ? .alreadyFriends
                            : .other(error.localizedDescription)
                        await send(.inviteAcceptFailed(failure))
                    }
                }

            case .inviteCodeGenerated(let code):
                state.generatedInviteCode = code
                return .none

            case .existingInviteCodeLoaded(let code):
                state.generatedInviteCode = code
                return .none

            case .friendsLoaded(let friends):
                state.isLoading = false
                state.friends = IdentifiedArray(uniqueElements: friends)
                return .none

            case .remoteFriendsLoaded(let remote):
                state.isLoading = false
                state.lastFetchedAt = .now
                let remoteArray = IdentifiedArray(uniqueElements: remote)
                let changed = remoteArray != state.friends
                print("[FriendsFeature] remote fetch succeeded, changed=\(changed), count=\(remote.count)")
                if changed {
                    state.friends = remoteArray
                    let userID = state.me.id
                    return .run { _ in
                        friendsCacheClient.save(remote, userID)
                    }
                }
                return .none

            case .remoteFetchFailed(let error):
                state.isLoading = false
                if !state.friends.isEmpty {
                    print("[FriendsFeature] remote fetch failed (cached): \(error)")
                } else {
                    state.banner = error
                    print("[FriendsFeature] remote fetch failed (no cache): \(error)")
                }
                return .none

            case .loadFailed(let error):
                state.isLoading = false
                state.banner = error
                return .none

            case .inviteAccepted(let friend):
                state.friends.append(friend)
                state.pastedInviteCode = ""
                state.banner = "好友已確認，可開始傳送訊息"
                return .none

            case .inviteAcceptFailed(let failure):
                state.inviteAcceptError = failure
                return .none

            case .inviteAcceptErrorDismissed:
                state.inviteAcceptError = nil
                return .none

            case .logoutConfirmTapped:
                state.isConfirmingLogout = true
                return .none

            case .logoutCancelled:
                state.isConfirmingLogout = false
                return .none

            case .logoutTapped:
                state.isConfirmingLogout = false
                let userID = state.me.id
                return .merge(
                    .cancel(id: CancelID.realtimeSubscription),
                    .run { send in
                        friendsCacheClient.clear(userID)
                        try? await authClient.signOut()
                        await send(.logoutSucceeded)
                    }
                )

            case .logoutSucceeded:
                return .none

            case .foregroundRefresh:
                state.lastFetchedAt = nil
                return .run { [id = state.me.id] send in
                    do {
                        let friends = try await friendClient.fetchFriends(id)
                        await send(.remoteFriendsLoaded(friends))
                    } catch {
                        await send(.remoteFetchFailed(error.localizedDescription))
                    }
                }

            case .realtimeChangeDetected:
                return .run { [id = state.me.id] send in
                    do {
                        let friends = try await friendClient.fetchFriends(id)
                        await send(.remoteFriendsLoaded(friends))
                    } catch {
                        await send(.remoteFetchFailed(error.localizedDescription))
                    }
                }

            case .removeFriendSwiped(let friend):
                state.friendPendingDeletion = friend
                return .none

            case .removeFriendCancelled:
                state.friendPendingDeletion = nil
                return .none

            case .removeFriendConfirmed:
                guard let friend = state.friendPendingDeletion else { return .none }
                state.friendPendingDeletion = nil
                let friendID = friend.id
                return .run { [userID = state.me.id] send in
                    do {
                        try await friendClient.removeFriend(userID, friendID)
                        await send(.removeFriendSucceeded(friendID))
                    } catch {
                        await send(.removeFriendFailed(error.localizedDescription))
                    }
                }

            case .removeFriendSucceeded(let friendID):
                state.friends.remove(id: friendID)
                let updated = Array(state.friends)
                let userID = state.me.id
                return .run { _ in
                    friendsCacheClient.save(updated, userID)
                }

            case .removeFriendFailed(let error):
                state.banner = "刪除失敗：\(error)"
                return .none
            }
        }
    }
}
