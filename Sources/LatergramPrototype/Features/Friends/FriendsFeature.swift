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
        var me: UserProfile = UserProfile(displayName: "")
        var friends: IdentifiedArrayOf<Friend> = []
        var generatedInviteCode = ""
        var pastedInviteCode = ""
        var isLoading = false
        var isSharingInvite = false
        var inviteShareMessage = ""
        var lastFetchedAt: Date? = nil
        var friendPendingDeletion: Friend? = nil
        var showDeepLinkInviteAlert = false
        var inviteAcceptError: AcceptInviteFailure? = nil
        var path = StackState<SettingsFeature.State>()
        @Presents var compose: ComposeFeature.State?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case reset
        case settingsButtonTapped
        case generateInviteCodeTapped
        case shareInviteCodeTapped
        case copyInviteCodeTapped
        case shareSheetDismissed
        case revokeInviteCodeTapped
        case acceptInviteCodeTapped
        case inviteCodeGenerated(String)
        case existingInviteCodeLoaded(String)
        case friendsLoaded([Friend])
        case remoteFriendsLoaded([Friend])
        case loadFailed(String)
        case remoteFetchFailed(String)
        case inviteAccepted(Friend)
        case inviteAcceptFailed(AcceptInviteFailure)
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
        case friendTapped(Friend)
        case compose(PresentationAction<ComposeFeature.Action>)
        case path(StackActionOf<SettingsFeature>)
    }

    @Dependency(\.friendClient) var friendClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient
    @Dependency(\.sentryClient) var sentryClient

    enum CancelID { case realtimeSubscription }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .binding:
                return .none

            case .onAppear:

                let cached = friendsCacheClient.load(state.me.id)
                if !cached.isEmpty {
                    state.friends = IdentifiedArray(uniqueElements: cached)
                    state.isLoading = false
                } else {
                    state.isLoading = state.lastFetchedAt == nil
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
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_generate_tapped")
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
                sentryClient.addBreadcrumb(category: "nav", message: "deeplink.invite_alert")
                state.pastedInviteCode = code
                state.showDeepLinkInviteAlert = true
                return .none

            case .deepLinkAlertDismissed:
                state.showDeepLinkInviteAlert = false
                return .none

            case .shareInviteCodeTapped:
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_share_tapped")
                state.inviteShareMessage = "加我的 Latergram！\nlatergram://invite?code=\(state.generatedInviteCode)"
                state.isSharingInvite = true
                return .none

            case .copyInviteCodeTapped:
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_copy_code_tapped")
                return .none

            case .shareSheetDismissed:
                state.isSharingInvite = false
                return .none

            case .revokeInviteCodeTapped:
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_revoke_tapped")
                state.generatedInviteCode = ""
                return .run { [id = state.me.id] _ in
                    try? await friendClient.revokeInviteToken(id)
                }

            case .acceptInviteCodeTapped:
                let code = state.pastedInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[DeepLink] acceptInviteCodeTapped code='\(code)'")
                guard !code.isEmpty else {
                    sentryClient.addBreadcrumb(
                        category: "friends",
                        message: "friends.invite_accept_blocked",
                        level: .warning,
                        data: ["reason": "empty_code"]
                    )
                    return .none
                }
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_accept_started")
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
                sentryClient.addBreadcrumb(category: "friends", message: "friends.invite_generate_succeeded")
                state.generatedInviteCode = code
                return .none

            case .existingInviteCodeLoaded(let code):
                state.generatedInviteCode = code
                return .none

            case .friendsLoaded(let friends):
                state.isLoading = false
                let sorted = friends.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                state.friends = IdentifiedArray(uniqueElements: sorted)
                return .none

            case .remoteFriendsLoaded(let remote):
                state.isLoading = false
                state.lastFetchedAt = .now
                let sorted = remote.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                let remoteArray = IdentifiedArray(uniqueElements: sorted)
                let changed = remoteArray != state.friends

                if changed {
                    state.friends = remoteArray
                    let userID = state.me.id
                    return .run { _ in
                        friendsCacheClient.save(sorted, userID)
                    }
                }
                return .none

            case .remoteFetchFailed(let error):
                state.isLoading = false
                print("[FriendsFeature] remote fetch failed: \(error)")
                return .none

            case .loadFailed(let error):
                state.isLoading = false
                print("[FriendsFeature] load failed: \(error)")
                return .none

            case .inviteAccepted(let friend):
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.invite_accept_succeeded",
                    data: ["friendID": friend.id.uuidString]
                )
                state.friends.append(friend)
                state.friends.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                state.pastedInviteCode = ""
                return .none

            case .inviteAcceptFailed(let failure):
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.invite_accept_failed",
                    level: .warning,
                    data: ["reason": failure == .alreadyFriends ? "already_friends" : "other"]
                )
                state.inviteAcceptError = failure
                return .none

            case .inviteAcceptErrorDismissed:
                state.inviteAcceptError = nil
                return .none

            case .reset:
                state = State()
                return .cancel(id: CancelID.realtimeSubscription)

            case .friendTapped(let friend):
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.compose_opened",
                    data: ["friendID": friend.id.uuidString]
                )
                state.compose = ComposeFeature.State(
                    friend: friend,
                    senderID: state.me.id,
                    senderName: state.me.displayName
                )
                return .none

            case .compose(.presented(.sendSucceeded)):
                state.compose = nil
                return .none

            case .compose(.presented(.cancelTapped)):
                state.compose = nil
                return .none

            case .compose(.presented(.sendFailed)):
                state.compose = nil
                return .none

            case .compose(.presented(.delegate(.purchaseSucceeded(let profile)))):
                state.me = profile
                return .none

            case .compose:
                return .none

            case .settingsButtonTapped:
                sentryClient.addBreadcrumb(category: "nav", message: "settings.opened")
                state.path.append(SettingsFeature.State(me: state.me))
                return .none

            case .path:
                return .none

            case .foregroundRefresh:
                let now = Date()
                let shouldFetch = state.lastFetchedAt
                    .map { now.timeIntervalSince($0) >= 30 } ?? true
                guard shouldFetch else { return .none }
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
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.remove_tapped",
                    data: ["friendID": friendID.uuidString]
                )
                return .run { [userID = state.me.id] send in
                    do {
                        try await friendClient.removeFriend(userID, friendID)
                        await send(.removeFriendSucceeded(friendID))
                    } catch {
                        await send(.removeFriendFailed(error.localizedDescription))
                    }
                }

            case .removeFriendSucceeded(let friendID):
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.remove_succeeded",
                    data: ["friendID": friendID.uuidString]
                )
                state.friends.remove(id: friendID)
                let updated = Array(state.friends)
                let userID = state.me.id
                return .run { _ in
                    friendsCacheClient.save(updated, userID)
                }

            case .removeFriendFailed:
                sentryClient.addBreadcrumb(
                    category: "friends",
                    message: "friends.remove_failed",
                    level: .warning
                )
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            SettingsFeature()
        }
        .ifLet(\.$compose, action: \.compose) {
            ComposeFeature()
        }
    }
}
