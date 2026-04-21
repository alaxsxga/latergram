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
    @State private var focusedMessage: DelayedMessage? = nil

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
                                onOpenTapped: {
                                    focusedMessage = message
                                    store.send(.revealTapped(message.id))
                                },
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
        .overlay {
            if let msg = focusedMessage {
                RevealFocusOverlay(message: msg) {
                    focusedMessage = nil
                }
                .ignoresSafeArea()
            }
        }
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
    let onOpenTapped: () -> Void
    let onDelete: () -> Void

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
                        onOpenTapped()
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

// MARK: - Reveal Focus Overlay

private struct RevealFocusOverlay: View {
    let message: DelayedMessage
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var bodyVisible = false

    private var bodyMaxHeight: CGFloat {
        let count = message.body.count
        if count <= 80 { return 100 }
        if count <= 300 { return 200 }
        return 300
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isVisible ? 0.55 : 0)
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(message: message)

                Divider()

                if bodyVisible {
                    ScrollView {
                        Text(message.body)
                            .font(.system(size: 18))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: bodyMaxHeight)
                    .transition(.opacity)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
            .scaleEffect(isVisible ? 1.0 : 0.82)
            .offset(y: isVisible ? -32 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.25)) {
                    bodyVisible = true
                }
            }
        }
    }

    private func dismiss() {
        onDismiss()
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

// MARK: - Preview

#Preview("Reveal Animation") {
    RevealAnimationPreview()
}

private struct RevealAnimationPreview: View {
    static let userID = UUID()
    static let fakeMessages: [DelayedMessage] = [
        // 短（~30字）
        DelayedMessage(
            senderID: UUID(),
            receiverID: userID,
            senderName: "Yuni",
            receiverName: "Me",
            body: "Just wanted to say I'm really glad we're friends. That's it.",
            style: .heart,
            sentAt: Date().addingTimeInterval(-86400),
            unlockAt: Date().addingTimeInterval(-60),
            status: .readyToReveal
        ),
        // 中（~280字）
        DelayedMessage(
            senderID: UUID(),
            receiverID: userID,
            senderName: "Nong",
            receiverName: "Me",
            body: "I've been thinking about this for a while and wanted to put it into words before I forgot. You've been a really steady presence in my life lately, even when you probably didn't realize it. The small things you do — checking in, showing up, being consistent — they matter more than you know. I hope things are going well for you right now, and if they're not, I'm here.",
            style: .cool,
            sentAt: Date().addingTimeInterval(-7200),
            unlockAt: Date().addingTimeInterval(-30),
            status: .readyToReveal
        ),
        // 長（~350字）
        DelayedMessage(
            senderID: UUID(),
            receiverID: userID,
            senderName: "Alex",
            receiverName: "Me",
            body: "I've been meaning to write this for a while. There have been a lot of changes lately, and honestly it's been hard to keep up with everything. But every time things get overwhelming, I think about the people who genuinely make a difference — and you're one of them.\n\nYou might not notice it, but the way you treat the people around you is something a lot of others could learn from. You're patient, you listen, and you show up. I don't say that enough, so I wanted to make sure I said it now.\n\nHope this finds you well.",
            style: .warm,
            sentAt: Date().addingTimeInterval(-3600),
            unlockAt: Date().addingTimeInterval(-10),
            status: .readyToReveal
        ),
    ]

    @State private var focusedMessage: DelayedMessage? = nil

    var body: some View {
        ZStack {
            pageBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Self.fakeMessages) { message in
                        ReadyToOpenCard(
                            message: message,
                            now: Date(),
                            onOpenTapped: { focusedMessage = message },
                            onDelete: {}
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 16)
            }
        }
        .overlay {
            if let msg = focusedMessage {
                RevealFocusOverlay(message: msg) {
                    focusedMessage = nil
                }
                .ignoresSafeArea()
            }
        }
    }
}
