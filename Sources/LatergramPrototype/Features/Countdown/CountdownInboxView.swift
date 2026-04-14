import ComposableArchitecture
import LatergramCore
import SwiftUI

// MARK: - Design constants

private let cobaltBlue = Color(red: 0.0, green: 0.28, blue: 0.9)
private let pageBg = Color(red: 0.94, green: 0.93, blue: 1.0)

private func shortDuration(_ interval: TimeInterval) -> String {
    let secs = max(0, interval)
    let d = secs / 86400
    let h = secs / 3600
    let m = secs / 60
    if d >= 1 { return String(format: "%.1fD", d) }
    if h >= 1 { return String(format: "%.1fH", h) }
    return String(format: "%.0fM", m)
}

// MARK: - Main View

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
                            Text("收到").tag(0)
                            Text("送出").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        TabView(selection: $selectedTab) {
                            ReceivedPage(store: store).tag(0)
                            SentPage(store: store).tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("")
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

    // receivedPendingSortOrder is only rebuilt on messagesLoaded,
    // so a just-revealed message stays here until the next fetch —
    // the card switches to showing its body in place instead of the Open button.
    var readyToOpen: [DelayedMessage] {
        store.receivedPendingSortOrder
            .compactMap { store.messages[id: $0] }
            .filter { $0.receiverID == store.currentUserID && $0.status != .scheduled }
    }

    var countingDown: [DelayedMessage] {
        store.receivedPendingSortOrder
            .compactMap { store.messages[id: $0] }
            .filter { $0.receiverID == store.currentUserID && $0.status == .scheduled }
    }

    var revealed: [DelayedMessage] {
        store.revealedSortOrder
            .compactMap { store.messages[id: $0] }
            .filter { $0.receiverID == store.currentUserID }
    }

    var body: some View {
        List {
            if readyToOpen.isEmpty && countingDown.isEmpty && revealed.isEmpty {
                ContentUnavailableView(
                    "沒有收到的訊息",
                    systemImage: "timer",
                    description: Text("請請好友傳送一則倒數訊息給你")
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                if !readyToOpen.isEmpty {
                    Section {
                        ForEach(readyToOpen) { message in
                            ReadyToOpenCard(
                                message: message,
                                now: store.now,
                                onRevealTap: { store.send(.revealTapped(message.id)) },
                                onDelete: { store.send(.deleteTapped(message.id)) }
                            )
                            .cardRow()
                        }
                    } header: {
                        ReadyToOpenHeader(count: readyToOpen.count)
                    }
                }

                if !countingDown.isEmpty {
                    Section {
                        ForEach(countingDown) { message in
                            CountingDownCard(message: message, now: store.now)
                                .cardRow()
                        }
                    } header: {
                        CountingDownHeader()
                    }
                }

                if !revealed.isEmpty {
                    Section {
                        ForEach(revealed) { message in
                            RevealedReceivedCard(
                                message: message,
                                onDelete: { store.send(.deleteTapped(message.id)) }
                            )
                            .cardRow()
                        }
                    } header: {
                        InboxSectionHeader("已開啟")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(pageBg)
        .refreshable { await store.send(.refreshRequested).finish() }
        .tag(0)
    }
}

// MARK: - Sent Page

private struct SentPage: View {
    let store: StoreOf<CountdownInboxFeature>

    var pending: [DelayedMessage] {
        store.sentPendingSortOrder
            .compactMap { store.messages[id: $0] }
            .filter { $0.senderID == store.currentUserID }
    }

    var revealed: [DelayedMessage] {
        store.revealedSortOrder
            .compactMap { store.messages[id: $0] }
            .filter { $0.senderID == store.currentUserID }
    }

    var body: some View {
        List {
            if pending.isEmpty && revealed.isEmpty {
                ContentUnavailableView(
                    "沒有發送的訊息",
                    systemImage: "paperplane",
                    description: Text("傳送一則倒數訊息給好友")
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(pending) { message in
                        SentCard(
                            message: message,
                            now: store.now,
                            onDelete: message.unlockAt <= store.now
                                ? { store.send(.deleteTapped(message.id)) }
                                : nil
                        )
                        .cardRow()
                    }
                }
                if !revealed.isEmpty {
                    Section {
                        ForEach(revealed) { message in
                            SentCard(
                                message: message,
                                now: store.now,
                                onDelete: message.unlockAt <= store.now
                                    ? { store.send(.deleteTapped(message.id)) }
                                    : nil
                            )
                            .cardRow()
                        }
                    } header: {
                        InboxSectionHeader("已開啟")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(pageBg)
        .refreshable { await store.send(.refreshRequested).finish() }
        .tag(1)
    }
}

// MARK: - Sent Card

private struct SentCard: View {
    let message: DelayedMessage
    let now: Date
    var onDelete: (() -> Void)? = nil

    @State private var isBodyShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(message: message, name: "to \(message.receiverName)", onDelete: onDelete)

            Divider()

            if message.status == .scheduled {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "hourglass")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                                .font(.title2.monospacedDigit().bold())
                        }
                        Text("解鎖於 \(message.unlockAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    if message.status == .revealed {
                        Text("對方已開啟").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Text(isBodyShown ? "隱藏" : "查看內容")
                        .font(.caption)
                        .foregroundStyle(cobaltBlue)
                }

                if isBodyShown {
                    Text(message.body).font(.body)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { isBodyShown.toggle() }
    }
}

// MARK: - Section Headers

private struct ReadyToOpenHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.open.fill")
            Text("Ready to Open").fontWeight(.bold)
            Spacer()
            Text("\(count) NEW")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(cobaltBlue)
                .clipShape(Capsule())
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct CountingDownHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
            Text("Counting Down").fontWeight(.bold)
            Text("Sealed for your future self")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct InboxSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.vertical, 2)
    }
}

// MARK: - Style Avatar

private struct StyleAvatar: View {
    let style: MessageStyle
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(style.background)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: style.icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(style.accent)
            )
    }
}

// MARK: - Shared Card Header

private struct CardHeader: View {
    let message: DelayedMessage
    var name: String? = nil
    var onDelete: (() -> Void)? = nil

    private var displayName: String { name ?? message.senderName }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StyleAvatar(style: message.style, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                Text("發送於 \(message.sentAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("總倒數 \(shortDuration(message.unlockAt.timeIntervalSince(message.sentAt)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("刪除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Ready to Open Card

private struct ReadyToOpenCard: View {
    let message: DelayedMessage
    let now: Date
    let onRevealTap: () -> Void
    let onDelete: () -> Void

    @State private var isRevealing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(message: message, onDelete: onDelete)

            Divider()

            if message.status == .revealed {
                Text(message.body).font(.body)
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isRevealing = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onRevealTap()
                            isRevealing = false
                        }
                    } label: {
                        Text("Open")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 36)
                            .padding(.vertical, 10)
                            .background(cobaltBlue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .opacity(isRevealing ? 0.5 : 1)
    }
}

// MARK: - Counting Down Card

private struct CountingDownCard: View {
    let message: DelayedMessage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(message: message)

            Divider()

            HStack {
                Spacer()
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                            .font(.title2.monospacedDigit().bold())
                    }
                    Text("解鎖於 \(message.unlockAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
    }
}

// MARK: - Revealed Received Card

private struct RevealedReceivedCard: View {
    let message: DelayedMessage
    let onDelete: () -> Void

    @State private var isBodyHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(message: message, onDelete: onDelete)

            Divider()

            if isBodyHidden {
                Text("點擊查看")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(message.body).font(.body)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { isBodyHidden.toggle() }
    }
}

// MARK: - View Modifier

private extension View {
    func cardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
