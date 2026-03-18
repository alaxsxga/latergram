import ComposableArchitecture
import LatergramCore
import SwiftUI

struct CountdownInboxView: View {
    @Bindable var store: StoreOf<CountdownInboxFeature>

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.messages.isEmpty {
                    ContentUnavailableView(
                        "沒有倒數訊息",
                        systemImage: "timer",
                        description: Text("請請好友傳送一則倒數訊息給你")
                    )
                } else {
                    List {
                        ForEach(store.messages) { message in
                            CountdownCard(message: message, now: store.now) {
                                store.send(.revealTapped(message.id))
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("倒數訊息")
            .onAppear { store.send(.onAppear) }
            .safeAreaInset(edge: .bottom) {
                if let banner = store.infoBanner {
                    Text(banner)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
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
    }
}

// MARK: - Card

private struct CountdownCard: View {
    let message: DelayedMessage
    let now: Date
    let onRevealTap: () -> Void

    @State private var isRevealing = false
    @State private var isBodyHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label(message.senderName, systemImage: message.style.icon)
                    .foregroundStyle(message.style.accent)
                Spacer()
                statusBadge
            }

            // Meta: sent time + total duration
            HStack {
                Text("發送於 \(message.sentAt.formatted(date: .abbreviated, time: .shortened))")
                Spacer()
                Text("總倒數 \(totalDurationText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            // Content
            if message.status == .revealed && !isBodyHidden {
                Text(message.body).font(.body)
                Text("隱藏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .highPriorityGesture(TapGesture().onEnded { isBodyHidden = true })
            } else if canTapReveal || isBodyHidden {
                Text("點擊開啟").font(.subheadline)
            } else {
                Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.style.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isRevealing ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if message.status == .revealed && isBodyHidden {
                isBodyHidden = false
                return
            }
            guard canTapReveal else { return }
            withAnimation(.easeInOut(duration: 0.3)) { isRevealing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onRevealTap()
                isRevealing = false
            }
        }
    }

    private var canTapReveal: Bool {
        message.status == .readyToReveal || (message.status == .scheduled && now >= message.unlockAt)
    }

    private var totalDurationText: String {
        let seconds = max(0, Int(message.unlockAt.timeIntervalSince(message.sentAt)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)小時\(m)分" }
        return "\(m)分"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch message.status {
        case .revealed:
            Text("已開啟").font(.caption).foregroundStyle(.green)
        case .readyToReveal:
            Text("可開啟").font(.caption).foregroundStyle(message.style.accent)
        case .scheduled:
            EmptyView()
        }
    }
}
