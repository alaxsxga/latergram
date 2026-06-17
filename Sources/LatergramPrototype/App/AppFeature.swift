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
        var lastEntitlementVerifiedAt: Date? = nil
        var forceUpdateRequired: Bool = false
    }

    enum Action {
        case onAppear
        case sessionChecked(UserProfile?)
        case tabSelected(Tab)
        case scenePhaseChanged(ScenePhase)
        case notificationTapped(messageID: UUID)
        case profileRefreshed(UserProfile)
        case entitlementVerified(UserProfile?, at: Date)
        case urlOpened(URL)
        case updateCheckCompleted(isRequired: Bool)
        case auth(AuthFeature.Action)
        case countdown(CountdownInboxFeature.Action)
        case friends(FriendsFeature.Action)
        case chats(ChatsFeature.Action)
    }

    private enum CancelID { case notificationTap, transactionUpdates }

    // 訂閱不會在分鐘級別變動，foreground 進入 1 小時內不重複 verifyAndSyncEntitlement。
    // 避免反覆切前後景時打 Edge Function 浪費電與額度。
    private static let entitlementThrottle: TimeInterval = 3600

    @Dependency(\.authClient) var authClient
    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.currentUserClient) var currentUserClient
    @Dependency(\.purchaseClient) var purchaseClient
    @Dependency(\.sentryClient) var sentryClient
    @Dependency(\.appConfigClient) var appConfigClient
    @Dependency(\.date) var date

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
                    .cancellable(id: CancelID.transactionUpdates),
                    .run { [appConfigClient] send in
                        let minVersion = (try? await appConfigClient.fetchMinIOSVersion()) ?? "0.0.0"
                        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                        await send(.updateCheckCompleted(isRequired: isVersionLessThan(current, minVersion)))
                    }
                )

            case .sessionChecked(let user):
                if let user {
                    state.currentUser = user
                    currentUserClient.update(user)
                    sentryClient.identify(userID: user.id, displayName: user.displayName)
                    sentryClient.addBreadcrumb(category: "nav", message: "route.main.cold_start")
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
                        .run { [purchaseClient, date] send in
                            let profile = try? await purchaseClient.verifyAndSyncEntitlement()
                            await send(.entitlementVerified(profile, at: date()))
                        }
                    )
                } else {
                    sentryClient.addBreadcrumb(category: "nav", message: "route.auth")
                    state.route = .auth(AuthFeature.State())
                }
                return .none

            case .auth(.succeeded(let user)):
                state.currentUser = user
                currentUserClient.update(user)
                sentryClient.identify(userID: user.id, displayName: user.displayName)
                sentryClient.addBreadcrumb(category: "nav", message: "route.main.signin")
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
                    .run { [purchaseClient, date] send in
                        let profile = try? await purchaseClient.verifyAndSyncEntitlement()
                        await send(.entitlementVerified(profile, at: date()))
                    }
                )

            case .auth:
                return .none

            case .urlOpened(let url):
                print("[DeepLink] urlOpened: \(url.absoluteString)")
                print("[DeepLink] scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")

                // Auth callback (email confirmation or password recovery)
                if url.scheme == "latergram", url.host == "auth" {
                    guard case .auth = state.route else {
                        print("[DeepLink] auth callback 進來但 route=\(state.route.debugLabel) 非 .auth，丟棄")
                        sentryClient.addBreadcrumb(
                            category: "nav",
                            message: "deeplink.auth_dropped_wrong_route",
                            level: .warning,
                            data: ["route": state.route.debugLabel]
                        )
                        return .none
                    }
                    let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let linkType = urlComponents?.queryItems?.first(where: { $0.name == "type" })?.value
                        ?? fragmentQueryItem(named: "type", in: url)
                    let isRecovery = linkType == "recovery"
                    sentryClient.addBreadcrumb(
                        category: "nav",
                        message: isRecovery ? "deeplink.auth_recovery" : "deeplink.auth"
                    )
                    return .run { send in
                        do {
                            let userID = try await authClient.handleDeepLink(url)
                            if isRecovery {
                                await send(.auth(.passwordResetLinkOpened))
                            } else {
                                await send(.auth(.emailConfirmed(userID)))
                            }
                        } catch {
                            sentryClient.addBreadcrumb(
                                category: "nav",
                                message: "deeplink.auth_failed",
                                level: .warning,
                                data: ["error": error.localizedDescription]
                            )
                            await send(.auth(.failed(error.localizedDescription)))
                        }
                    }
                }

                // Invite deep link
                guard url.scheme == "latergram",
                      url.host == "invite",
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    print("[DeepLink] URL 格式不符，略過: \(url.absoluteString)")
                    sentryClient.addBreadcrumb(
                        category: "nav",
                        message: "deeplink.unknown",
                        level: .warning,
                        data: [
                            "scheme": url.scheme ?? "nil",
                            "host": url.host ?? "nil",
                            "url": url.absoluteString
                        ]
                    )
                    return .none
                }
                print("[DeepLink] code=\(code), route=\(state.route)")
                sentryClient.addBreadcrumb(category: "nav", message: "deeplink.invite")

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

            case .entitlementVerified(let profile, let at):
                // 失敗（profile == nil）也記 timestamp 太激進——保持 throttle 是「成功過 1 小時內不重跑」語意，
                // 失敗就讓下次 scene active 自然 retry。
                if let profile {
                    state.lastEntitlementVerifiedAt = at
                    return .send(.profileRefreshed(profile))
                }
                return .none

            case .updateCheckCompleted(let isRequired):
                state.forceUpdateRequired = isRequired
                return .none

            case .notificationTapped:
                sentryClient.addBreadcrumb(category: "nav", message: "tab.inbox.via_push")
                state.selectedTab = .countdown
                return .none

            case .tabSelected(let tab):
                sentryClient.addBreadcrumb(category: "nav", message: "tab.\(tab.breadcrumbName)")
                state.selectedTab = tab
                return .none

            case .scenePhaseChanged(.active):
                guard state.route == .main else { return .none }
                let now = date()
                let shouldVerifyEntitlement = state.lastEntitlementVerifiedAt
                    .map { now.timeIntervalSince($0) >= Self.entitlementThrottle }
                    ?? true
                let verifyEffect: Effect<Action> = shouldVerifyEntitlement
                    ? .run { [purchaseClient, date] send in
                        let profile = try? await purchaseClient.verifyAndSyncEntitlement()
                        await send(.entitlementVerified(profile, at: date()))
                    }
                    : .none
                return .merge(
                    .send(.countdown(.foregroundRefresh)),
                    .send(.chats(.foregroundRefresh)),
                    .send(.friends(.foregroundRefresh)),
                    verifyEffect
                )

            case .scenePhaseChanged(.background):
                return .merge(
                    .cancel(id: CountdownInboxFeature.CancelID.load),
                    .cancel(id: ChatsFeature.CancelID.load)
                )

            case .scenePhaseChanged:
                return .none

            case .friends(.path(.element(_, .delegate(.logoutSucceeded)))):
                sentryClient.addBreadcrumb(category: "nav", message: "route.auth.logout")
                state.currentUser = nil
                currentUserClient.update(UserProfile(displayName: ""))
                sentryClient.clearUser()
                state.countdown = CountdownInboxFeature.State()
                state.selectedTab = .countdown
                state.route = .auth(AuthFeature.State())
                state.lastEntitlementVerifiedAt = nil
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

            case .friends(.path(.element(_, .delegate(.purchaseSucceeded(let profile))))):
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

// MARK: - Version helpers

private func isVersionLessThan(_ current: String, _ minimum: String) -> Bool {
    let cur = current.split(separator: ".").compactMap { Int($0) }
    let min = minimum.split(separator: ".").compactMap { Int($0) }
    let count = max(cur.count, min.count)
    for i in 0..<count {
        let c = i < cur.count ? cur[i] : 0
        let m = i < min.count ? min[i] : 0
        if c < m { return true }
        if c > m { return false }
    }
    return false
}

// MARK: - URL helpers

private func fragmentQueryItem(named name: String, in url: URL) -> String? {
    guard let fragment = url.fragment else { return nil }
    return URLComponents(string: "?\(fragment)")?.queryItems?.first(where: { $0.name == name })?.value
}

// MARK: - Breadcrumb helper

extension AppFeature.Tab {
    var breadcrumbName: String {
        switch self {
        case .friends: return "friends"
        case .countdown: return "inbox"
        case .chats: return "chats"
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

    var debugLabel: String {
        switch self {
        case .splash: return "splash"
        case .auth: return "auth"
        case .main: return "main"
        }
    }
}
