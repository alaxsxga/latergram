import ComposableArchitecture
import SwiftUI

public struct AppView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let store: StoreOf<AppFeature>

    public init() {
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    }

    public var body: some View {
        Group {
            switch store.route {
            case .splash:
                ProgressView()
                    .onAppear { store.send(.onAppear) }

            case .auth:
                if let authStore = store.scope(state: \.route.authState, action: \.auth) {
                    AuthView(store: authStore)
                }

            case .main:
                mainTabView
                    .onChange(of: scenePhase) { _, newPhase in
                        store.send(.scenePhaseChanged(newPhase))
                    }
            }
        }
        .onOpenURL { url in
            store.send(.urlOpened(url))
        }
    }

    private var mainTabView: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            FriendsProfileView(store: store.scope(state: \.friends, action: \.friends))
                .tabItem { Label("好友", systemImage: "person.2") }
                .tag(AppFeature.Tab.friends)

            CountdownInboxView(store: store.scope(state: \.countdown, action: \.countdown))
                .tabItem { Label("倒數", systemImage: "timer") }
                .tag(AppFeature.Tab.countdown)

            ChatsView(store: store.scope(state: \.chats, action: \.chats))
                .tabItem { Label("聊天", systemImage: "message") }
                .tag(AppFeature.Tab.chats)
        }
    }
}
