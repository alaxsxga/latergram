import ComposableArchitecture
import LatergramCore
import SwiftUI

struct CountdownInboxView: View {
    @Bindable var store: StoreOf<CountdownInboxFeature>
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedTab) {
                            Text("接收").tag(0)
                            Text("發送").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        TabView(selection: $selectedTab) {
                            ReceivedPage(store: store)
                                .tag(0)
                            SentPage(store: store)
                                .tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("倒數訊息")
            .navigationBarTitleDisplayMode(.inline)
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
                set: { if !$0 { store.send(.errorDismissed) } }
            )) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Received Page

private struct ReceivedPage: View {
    let store: StoreOf<CountdownInboxFeature>

    var received: [DelayedMessage] {
        store.messages.filter { $0.receiverID == store.currentUserID }
    }

    var body: some View {
        List {
            if received.isEmpty {
                ContentUnavailableView(
                    "沒有收到的訊息",
                    systemImage: "timer",
                    description: Text("請請好友傳送一則倒數訊息給你")
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(received) { message in
                    CountdownCard(message: message, now: store.now) {
                        store.send(.revealTapped(message.id))
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.send(.refreshRequested).finish() }
        .tag(0)
    }
}

// MARK: - Sent Page

private struct SentPage: View {
    let store: StoreOf<CountdownInboxFeature>

    var sent: [DelayedMessage] {
        store.messages.filter { $0.senderID == store.currentUserID }
    }

    var body: some View {
        List {
            if sent.isEmpty {
                ContentUnavailableView(
                    "沒有發送的訊息",
                    systemImage: "paperplane",
                    description: Text("傳送一則倒數訊息給好友")
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(sent) { message in
                    SentCard(message: message, now: store.now)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.send(.refreshRequested).finish() }
        .tag(1)
    }
}

// MARK: - Sent Card

private struct SentCard: View {
    let message: DelayedMessage
    let now: Date

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: style icon only, no sender name
            HStack {
                Image(systemName: message.style.icon)
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
            if isRevealed {
                Text(message.body).font(.body)
                Text("隱藏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .highPriorityGesture(TapGesture().onEnded { isRevealed = false })
            } else {
                Text("點擊開啟").font(.subheadline)
            }

            // Countdown: show while scheduled so sender knows when receiver can open
            if message.status == .scheduled {
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
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !isRevealed else { return }
            isRevealed = true
        }
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
        case .readyToReveal, .scheduled:
            EmptyView()
        }
    }
}

// MARK: - Received Card

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
