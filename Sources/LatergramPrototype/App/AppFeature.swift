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
        case loggedOut
        case profileRefreshed(UserProfile)
        case urlOpened(URL)
        case auth(AuthFeature.Action)
        case countdown(CountdownInboxFeature.Action)
        case friends(FriendsFeature.Action)
        case chats(ChatsFeature.Action)
    }

    private enum CancelID { case notificationTap }

    @Dependency(\.authClient) var authClient
    @Dependency(\.notificationClient) var notificationClient

    var body: some ReducerOf<Self> {
        Scope(state: \.countdown, action: \.countdown) { CountdownInboxFeature() }
        Scope(state: \.friends, action: \.friends) { FriendsFeature() }
        Scope(state: \.chats, action: \.chats) { ChatsFeature() }

        Reduce { state, action in
            switch action {

            case .onAppear:
                let nc = notificationClient
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
                    .cancellable(id: CancelID.notificationTap)
                )

            case .sessionChecked(let user):
                if let user {
                    state.currentUser = user
                    CurrentUserStore.shared.user = user
                    state.friends.me = user
                    state.countdown.currentUserID = user.id
                    state.chats.currentUserID = user.id
                    state.route = .main
                    if let code = state.pendingInviteCode {
                        print("[DeepLink] sessionChecked — 發現 pendingInviteCode=\(code)，處理中")
                        state.pendingInviteCode = nil
                        state.selectedTab = .friends
                        return .send(.friends(.acceptInviteFromDeepLink(code)))
                    }
                    return .send(.chats(.foregroundRefresh))
                } else {
                    state.route = .auth(AuthFeature.State())
                }
                return .none

            case .auth(.succeeded(let user)):
                state.currentUser = user
                CurrentUserStore.shared.user = user
                state.friends.me = user
                state.countdown.currentUserID = user.id
                state.chats.currentUserID = user.id
                state.route = .main
                if let code = state.pendingInviteCode {
                    state.pendingInviteCode = nil
                    state.selectedTab = .friends
                    return .send(.friends(.acceptInviteFromDeepLink(code)))
                }
                return .send(.chats(.foregroundRefresh))

            case .auth:
                return .none

            case .urlOpened(let url):
                print("[DeepLink] urlOpened: \(url.absoluteString)")
                print("[DeepLink] scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil")")
                guard url.scheme == "delaygram",
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
                CurrentUserStore.shared.user = user
                return .send(.chats(.messageLimitUpdated(user.messageLimit)))

            case .loggedOut:
                state.currentUser = nil
                state.route = .auth(AuthFeature.State())
                return .none

            case .notificationTapped:
                state.selectedTab = .countdown
                return .none

            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none

            case .scenePhaseChanged(.active):
                guard state.route == .main else { return .none }
                // TODO: 測試用，IAP 完成後移除 profile re-fetch（改用 profileRefreshed 在購買成功時呼叫）
                return .merge(
                    .send(.countdown(.foregroundRefresh)),
                    .send(.chats(.foregroundRefresh)),
                    .send(.friends(.foregroundRefresh)),
                    .run { [authClient] send in
                        let user = await authClient.currentSession()
                        if let user { await send(.profileRefreshed(user)) }
                    }
                )

            case .scenePhaseChanged:
                return .none

            case .friends(.logoutSucceeded):
                state.currentUser = nil
                CurrentUserStore.shared.user = UserProfile(displayName: "", username: "")
                state.friends = FriendsFeature.State()
                state.countdown = CountdownInboxFeature.State()
                state.chats = ChatsFeature.State()
                state.route = .auth(AuthFeature.State())
                return .merge(
                    .cancel(id: ChatsFeature.CancelID.load),
                    .cancel(id: CountdownInboxFeature.CancelID.timer),
                    .cancel(id: CountdownInboxFeature.CancelID.load)
                )

            case .chats(.path(.element(_, .delegate(.messageSent(let message))))):
                return .send(.countdown(.messageSent(message)))

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
