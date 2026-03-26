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
                Button { store.send(.composeTapped) } label: {
                    if store.isAtSendLimit, let unlockAt = store.earliestBlockedUnlockAt {
                        Label(CountdownFormatter.dHms(from: unlockAt.timeIntervalSince(store.now)),
                              systemImage: "clock")
                    } else {
                        Text("建立訊息")
                    }
                }
            }
        }
        .onAppear { store.send(.onAppear) }
        .sheet(item: $store.scope(state: \.compose, action: \.compose)) { composeStore in
            ComposeView(store: composeStore)
        }
        .sheet(isPresented: Binding(
            get: { store.showLimitInfo },
            set: { if !$0 { store.send(.limitInfoDismissed) } }
        )) {
            LimitInfoSheet(
                unlockAt: store.earliestBlockedUnlockAt,
                now: store.now,
                onDismiss: { store.send(.limitInfoDismissed) }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .alert("錯誤", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.send(.errorDismissed) } }
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
                        isMine: message.senderID == store.state.friend.id ? false : true,
                        onRevealTap: { store.send(.revealTapped(message.id)) },
                        onDelete: message.unlockAt <= store.now
                            ? { store.send(.deleteTapped(message.id)) }
                            : nil
                    )
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

// MARK: - Limit Info Sheet

private struct LimitInfoSheet: View {
    let unlockAt: Date?
    let now: Date
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 6) {
                if let unlockAt {
                    Text(CountdownFormatter.dHms(from: unlockAt.timeIntervalSince(now)))
                        .font(.title.monospacedDigit().bold())
                }
                Text("前一則訊息開啟後才能再傳給同一位好友")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    // TODO: IAP — 導向購買頁
                    onDismiss()
                } label: {
                    Label("解鎖更多上限", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("知道了", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: DelayedMessage
    let now: Date
    let isMine: Bool
    let onRevealTap: () -> Void
    var onDelete: (() -> Void)? = nil

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
                    .contextMenu {
                        if let onDelete {
                            Button(role: .destructive) { onDelete() } label: {
                                Label("刪除此訊息", systemImage: "trash")
                            }
                        }
                    }
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
