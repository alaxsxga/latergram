#if os(iOS)
import ComposableArchitecture
import SwiftUI

public struct AppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var store: StoreOf<AppFeature>

    public init() {
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    }

    public var body: some View {
        Group {
            switch store.route {
            case .splash:
                Color(red: 0.949, green: 0.949, blue: 0.949)
                    .ignoresSafeArea()
                    .onAppear { store.send(.onAppear) }

            case .auth:
                if let authStore = store.scope(state: \.route.authState, action: \.auth) {
                    AuthView(store: authStore)
                }

            case .main:
                mainTabView
                    .id(store.currentUser?.id)
                    .onChange(of: scenePhase) { _, newPhase in
                        store.send(.scenePhaseChanged(newPhase))
                    }
                    .fullScreenCover(
                        item: $store.scope(state: \.onboarding, action: \.onboarding)
                    ) { onboardingStore in
                        OnboardingView(store: onboardingStore)
                    }
            }
        }
        .alert(
            Text(LS("force_update.title")),
            isPresented: Binding(get: { store.forceUpdateRequired }, set: { _ in }),
            actions: {
                Button(LS("force_update.button")) {
                    UIApplication.shared.open(LegalURLs.appStore)
                }
            },
            message: {
                L("force_update.body")
            }
        )
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
                .tabItem { Label(LS("tab.friends"), systemImage: "person.2") }
                .tag(AppFeature.Tab.friends)

            CountdownInboxView(store: store.scope(state: \.countdown, action: \.countdown))
                .tabItem { Label(LS("tab.inbox"), systemImage: "envelope") }
                .tag(AppFeature.Tab.countdown)

            ChatsView(store: store.scope(state: \.chats, action: \.chats))
                .tabItem { Label(LS("tab.chats"), systemImage: "arrow.left.arrow.right") }
                .tag(AppFeature.Tab.chats)
        }
        .tint(Color.brand)
        .preferredColorScheme(.dark)
    }
}
#endif
