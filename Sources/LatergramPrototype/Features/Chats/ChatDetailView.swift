import ComposableArchitecture
import LatergramCore
import SwiftUI

struct ChatDetailView: View {
    @Bindable var store: StoreOf<ChatDetailFeature>

    var body: some View {
        Group {
            if store.isLoading && store.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.messages.isEmpty {
                ContentUnavailableView(
                    "還沒有訊息",
                    systemImage: "bubble.left",
                    description: Text("傳送第一則倒數訊息吧")
                )
            } else {
                messageList
            }
        }
        .navigationTitle(store.friend.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("建立訊息") { store.send(.composeTapped) }
            }
        }
        .onAppear { store.send(.onAppear) }
        .sheet(item: $store.scope(state: \.compose, action: \.compose)) { composeStore in
            ComposeView(store: composeStore)
        }
        .alert("錯誤", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.send(.loadFailed("")) } }
        )) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.messages) { message in
                    MessageBubble(
                        message: message,
                        now: store.now,
                        isMine: message.senderID == store.state.friend.id ? false : true
                    ) {
                        store.send(.revealTapped(message.id))
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .id(message.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: store.messages.count) {
                if let last = store.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: DelayedMessage
    let now: Date
    let isMine: Bool
    let onRevealTap: () -> Void

    @State private var isRevealing = false

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                bubbleContent
                    .padding(10)
                    .background(message.style.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(isRevealing ? 0.4 : 1)
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.status == .revealed || isMine {
            Text(message.body)
        } else if message.status == .readyToReveal ||
                  (message.status == .scheduled && now >= message.unlockAt) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isRevealing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onRevealTap()
                    isRevealing = false
                }
            } label: {
                Label("點擊開啟", systemImage: message.style.icon)
                    .foregroundStyle(message.style.accent)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                    .font(.caption.monospacedDigit())
                Text("尚未解鎖").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
