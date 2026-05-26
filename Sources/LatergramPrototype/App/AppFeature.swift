import ComposableArchitecture
import LatergramCore
import SwiftUI

@Reducer
struct AppFeature {
    enum Route: Equatable {
        case splash
        case auth(AuthFeature.State)
        case main
    }

    enum Tab: Int, Equatable {
        case friends = 0
        case countdown = 1
        case chats = 2
    }

    @ObservableState
    struct State: Equatable {
        var route: Route = .splash
        var currentUser: UserProfile?
        var selectedTab: Tab = .countdown
        var countdown = CountdownInboxFeature.State()
        var friends = FriendsFeature.State()
        var chats = ChatsFeature.State()
        var pendingInviteCode: String? = nil
    }

    enum Action {
        case onAppear
        case sessionChecked(UserProfile?)
        case tabSelected(Tab)
        case scenePhaseChanged(ScenePhase)
        case notificationTapped(messageID: UUID)
        case profileRefreshed(UserProfile)
        case urlOpened(URL)
        case auth(AuthFeature.Action)
        case countdown(CountdownInboxFeature.Action)
        case friends(FriendsFeature.Action)
        case chats(ChatsFeature.Action)
    }

    private enum CancelID { case notificationTap, transactionUpdates }

    @Dependency(\.authClient) var authClient
    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.currentUserClient) var currentUserClient
    @Dependency(\.purchaseClient) var purchaseClient

    var body: some ReducerOf<Self> {
        Scope(state: \.countdown, action: \.countdown) { CountdownInboxFeature() }
        Scope(state: \.friends, action: \.friends) { FriendsFeature() }
        Scope(state: \.chats, action: \.chats) { ChatsFeature() }

        Reduce { state, action in
            switch action {

            case .onAppear:
                let nc = notificationClient
                let pc = purchaseClient
                return .merge(
                    .run { send in
                        let user = await authClient.currentSession()
                        await send(.sessionChecked(user))
                    },
                    .run { send in
                        for await messageID in nc.notificationTapStream() {
                            await send(.notificationTapped(messageID: messageID))
                        }
                    }
                    .cancellable(id: CancelID.notificationTap),
                    .run { send in
                        for await profile in pc.observeTransactionUpdates() {
                            await send(.profileRefreshed(profile))
                        }
                    }
                    .cancellable(id: CancelID.transactionUpdates)
                )

            case .sessionChecked(let user):
                if let user {
                    state.currentUser = user
                    currentUserClient.update(user)
                    state.friends.me = user
                    state.countdown.currentUserID = user.id
                    state.countdown.currentUserName = user.displayName
                    state.chats.currentUserID = user.id
                    state.chats.currentUserName = user.displayName
                    state.route = .main
                    if let code = state.pendingInviteCode {
                        print("[DeepLink] sessionChecked — 發現 pendingInviteCode=\(code)，處理中")
                        state.pendingInviteCode = nil
                        state.selectedTab = .friends
                        return .send(.friends(.acceptInviteFromDeepLink(code)))
                    }
                    return .merge(
                        .send(.countdown(.refreshRequested)),
                        .send(.chats(.foregroundRefresh)),
                        .run { [purchaseClient] send in
                            if let profile = try? await purchaseClient.verifyAndSyncEntitlement() {
                                await send(.profileRefreshed(profile))
                            }
                        }
                    )
                } else {
                    state.route = .auth(AuthFeature.State())
                }
                return .none

            case .auth(.succeeded(let user)):
                state.currentUser = user
                currentUserClient.update(user)
                state.friends.me = user
                state.countdown.currentUserID = user.id
                state.countdown.currentUserName = user.displayName
                state.chats.currentUserID = user.id
                state.chats.currentUserName = user.displayName
                state.route = .main
                if let code = state.pendingInviteCode {
                    state.pendingInviteCode = nil
                    state.selectedTab = .friends
                    return .send(.friends(.acceptInviteFromDeepLink(code)))
                }
                return .merge(
                    .send(.countdown(.foregroundRefresh)),
                    .send(.chats(.foregroundRefresh)),
                    .run { [purchaseClient] send in
                        if let profile = try? await purchaseClient.verifyAndSyncEntitlement() {
                            await send(.profileRefreshed(profile))
                        }
                    }
                )

            case .auth:
                return .none

            case .urlOpened(let url):
                print("[DeepLink] urlOpened: \(url.absoluteString)")
                print("[DeepLink] scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")

                // Auth callback (email confirmation)
                if url.scheme == "latergram", url.host == "auth" {
                    guard case .auth = state.route else { return .none }
                    return .run { send in
                        do {
                            let userID = try await authClient.handleDeepLink(url)
                            await send(.auth(.emailConfirmed(userID)))
                        } catch {
                            print("[DeepLink] handleDeepLink 失敗: \(error)")
                        }
                    }
                }

                // Invite deep link
                guard url.scheme == "latergram",
                      url.host == "invite",
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    print("[DeepLink] URL 格式不符，略過")
                    return .none
                }
                print("[DeepLink] code=\(code), route=\(state.route)")

                if state.route == .main {
                    print("[DeepLink] App 已登入，直接處理")
                    state.selectedTab = .friends
                    return .send(.friends(.acceptInviteFromDeepLink(code)))
                } else {
                    print("[DeepLink] App 未在 main，暫存 pendingInviteCode")
                    state.pendingInviteCode = code
                    return .none
                }

            case .profileRefreshed(let user):
                state.currentUser = user
                currentUserClient.update(user)
                return .none

            case .notificationTapped:
                state.selectedTab = .countdown
                return .none

            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .scenePhaseChanged(.active):
                guard state.route == .main else { return .none }
                return .merge(
                    .send(.countdown(.foregroundRefresh)),
                    .send(.chats(.foregroundRefresh)),
                    .send(.friends(.foregroundRefresh)),
                    .run { [purchaseClient] send in
                        if let profile = try? await purchaseClient.verifyAndSyncEntitlement() {
                            await send(.profileRefreshed(profile))
                        }
                    }
                )

            case .scenePhaseChanged:
                return .none

            case .friends(.path(.element(_, .delegate(.logoutSucceeded)))):
                state.currentUser = nil
                currentUserClient.update(UserProfile(displayName: "", username: ""))
                state.countdown = CountdownInboxFeature.State()
                state.selectedTab = .countdown
                state.route = .auth(AuthFeature.State())
                // Send .reset to features with StackState so forEach(\.path) can
                // detect path elements being removed and cancel child effects
                // before state is wiped.
                return .merge(
                    .cancel(id: CountdownInboxFeature.CancelID.timer),
                    .cancel(id: CountdownInboxFeature.CancelID.load),
                    .cancel(id: CountdownInboxFeature.CancelID.messageStream),
                    .send(.chats(.reset)),
                    .send(.friends(.reset)),
                    .run { [notificationClient] _ in await notificationClient.cancelAll() }
                )

            case .chats(.path(.element(_, .delegate(.purchaseSucceeded(let profile))))):
                return .send(.profileRefreshed(profile))

            case .countdown(.delegate(.purchaseSucceeded(let profile))):
                return .send(.profileRefreshed(profile))

            case .chats(.path(.element(_, .delegate(.messageSent(let message))))):
                return .send(.countdown(.messageSent(message)))

            case .countdown(.messageSent(let message)):
                guard let currentUserID = state.currentUser?.id else { return .none }
                let friendID = message.senderID == currentUserID ? message.receiverID : message.senderID
                var updated = state.chats.latestMessages
                updated[friendID] = message
                return .send(.chats(.latestMessagesUpdated(updated)))

            case .countdown(.messagesLoaded(let messages)):
                guard let currentUserID = state.currentUser?.id else { return .none }
                var latest: [UUID: DelayedMessage] = [:]
                for msg in messages {
                    let friendID = msg.senderID == currentUserID ? msg.receiverID : msg.senderID
                    if let existing = latest[friendID] {
                        if msg.sentAt > existing.sentAt { latest[friendID] = msg }
                    } else {
                        latest[friendID] = msg
                    }
                }
                return .send(.chats(.latestMessagesUpdated(latest)))

            case .countdown, .friends, .chats:
                return .none
            }
        }
        .ifLet(\.route.authState, action: \.auth) {
            AuthFeature()
        }
    }
}

// MARK: - Route helper

extension AppFeature.Route {
    var authState: AuthFeature.State? {
        get {
            guard case .auth(let s) = self else { return nil }
            return s
        }
        set {
            guard let newValue else { return }
            self = .auth(newValue)
        }
    }
}
