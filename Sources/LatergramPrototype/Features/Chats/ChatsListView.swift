import ComposableArchitecture
import LatergramCore
import SwiftUI

struct ChatsView: View {
    @Bindable var store: StoreOf<ChatsFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            Group {
                if store.isLoading && store.friends.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.friends.isEmpty {
                    ContentUnavailableView(
                        "沒有聊天",
                        systemImage: "message",
                        description: Text("先去好友頁加好友吧")
                    )
                } else {
                    List(store.friends) { friend in
                        Button {
                            store.send(.friendTapped(friend))
                        } label: {
                            HStack {
                                Text(friend.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("聊天列表")
            .onAppear { store.send(.onAppear) }
        } destination: { chatStore in
            ChatDetailView(store: chatStore)
        }
    }
}
