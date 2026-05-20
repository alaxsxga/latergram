#if os(iOS)
import ComposableArchitecture
import LatergramCore
import SwiftUI

private let cardRadius: CGFloat = 22

private func shortDuration(_ interval: TimeInterval) -> String {
    let secs = max(0, interval)
    let d = secs / 86400
    let h = secs / 3600
    let m = secs / 60
    if d >= 1 { return String(format: "%.1fD", d) }
    if h >= 1 { return String(format: "%.1fH", h) }
    return String(format: "%.0fM", m)
}


// MARK: - MessageAvatar

private struct MessageAvatar: View {
    let name: String
    let style: MessageStyle
    let size: CGFloat
    var isReady: Bool = false

    private var bg: Color { isReady ? style.styleColor.opacity(0.18) : Color.surfaceMid }
    private var fg: Color { isReady ? style.styleTextColor : .white.opacity(0.85) }

    private var initials: String {
        let w = name.split(separator: " ")
        return w.count >= 2
            ? "\(w[0].prefix(1))\(w[1].prefix(1))".uppercased()
            : String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(bg)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(fg)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CardMeta (shared header row)

private struct CardMeta: View {
    let message: DelayedMessage
    var name: String? = nil
    var onDelete: (() -> Void)? = nil
    var isReady: Bool = false

    private var displayName: String { name ?? message.senderName }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MessageAvatar(name: displayName, style: message.style, size: 40, isReady: isReady)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(String(format: LS("inbox.card.sent_at"), message.sentAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fgMuted)
                Text(String(format: LS("inbox.card.total_countdown"), shortDuration(TimeInterval(message.delaySeconds))))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fgMuted)
            }

            Spacer()

            if let onDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label(LS("common.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
    }
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
                            L("inbox.tab.received").tag(0)
                            L("inbox.tab.sent").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
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
            .pageBackground()
            .navigationBarHidden(true)
            .onAppear { store.send(.onAppear) }
            .alert(L("common.error_title"), isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.errorDismissed) } }
            )) {
                Button(LS("common.ok"), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .sheet(isPresented: Binding(
                get: { store.showRecipientPicker },
                set: { if !$0 { store.send(.recipientPickerDismissed) } }
            )) {
                RecipientPickerSheet(
                    friends: store.friends,
                    isLoading: store.isLoadingFriends,
                    onSelect: { store.send(.recipientSelected($0)) }
                )
            }
            .sheet(isPresented: Binding(
                get: { store.showLimitInfo },
                set: { if !$0 { store.send(.limitInfoDismissed) } }
            )) {
                LimitInfoSheet(
                    unlockAt: store.limitInfoUnlockAt,
                    now: store.now,
                    onDismiss: { store.send(.limitInfoDismissed) }
                )
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $store.scope(state: \.compose, action: \.compose)) {
                ComposeView(store: $0)
            }
        }
    }
}

// MARK: - Received Page

private struct ReceivedPage: View {
    let store: StoreOf<CountdownInboxFeature>
    @State private var focusedMessage: DelayedMessage? = nil

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
            Section {
                ForEach(readyToOpen) { message in
                    ReadyToOpenCard(
                        message: message,
                        now: store.now,
                        onOpenTapped: {
                            focusedMessage = message
                            store.send(.revealTapped(message.id))
                        }
                    )
                    .cardRow()
                }
            } header: {
                ReadyToOpenHeader(count: readyToOpen.count, onComposeTapped: { store.send(.plusTapped) })
            }

            if countingDown.isEmpty && revealed.isEmpty && readyToOpen.isEmpty {
                ContentUnavailableView {
                    Label(LS("inbox.received.empty_title"), systemImage: "timer")
                } description: {
                    L("inbox.received.empty_description")
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
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
                        InboxSectionHeader("inbox.section.revealed")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBg)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 10) }
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
                ContentUnavailableView {
                    Label(LS("inbox.sent.empty_title"), systemImage: "paperplane")
                } description: {
                    L("inbox.sent.empty_description")
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { message in
                            SentCard(
                                message: message,
                                now: store.now,
                                onDelete: { store.send(.deleteTapped(message.id)) }
                            )
                            .cardRow()
                        }
                    } header: {
                        InboxSectionHeader("inbox.section.sent_pending")
                    }
                }
                if !revealed.isEmpty {
                    Section {
                        ForEach(revealed) { message in
                            SentCard(
                                message: message,
                                now: store.now,
                                onDelete: { store.send(.deleteTapped(message.id)) }
                            )
                            .cardRow()
                        }
                    } header: {
                        InboxSectionHeader("inbox.section.sent_opened")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.pageBg)
        .refreshable { await store.send(.refreshRequested).finish() }
        .tag(1)
    }
}

// MARK: - Counting Down Card

private struct CountingDownCard: View {
    let message: DelayedMessage
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            CardMeta(message: message)
                .padding(.bottom, 20)

            VStack(spacing: 6) {
                L("inbox.card.unlock_countdown")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Color.fgMuted)

                Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(message.style.styleColor)
                    .shadow(color: message.style.styleColor.opacity(0.35), radius: 12, x: 0, y: 0)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 4) {
                    Image(systemName: "lock").font(.caption)
                    Text(message.unlockAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                .foregroundStyle(Color.fgMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .messageCard(style: message.style, tier: .countingDown)
    }
}

// MARK: - Ready to Open Card

private struct ReadyToOpenCard: View {
    let message: DelayedMessage
    let now: Date
    let onOpenTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CardMeta(message: message, isReady: true)
                .padding(.bottom, 16)

            if message.status == .revealed {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [
                                message.style.styleColor.opacity(0.25),
                                message.style.styleColor.opacity(0.08)
                            ],
                            startPoint: .top, endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(message.style.styleColor.opacity(0.45), lineWidth: 1)
                    Image(systemName: "envelope")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(message.style.styleColor)
                }
                .frame(width: 56, height: 56)
                .shadow(color: message.style.styleColor.opacity(0.6), radius: 30, x: 0, y: -4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

                Button(action: onOpenTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open")
                            .font(.system(size: 16, weight: .heavy))
                        L("inbox.section.ready_to_open")
                            .font(.system(size: 16, weight: .heavy))
                    }
                    .foregroundStyle(Color(red: 0.102, green: 0.059, blue: 0.031))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(LinearGradient(
                        colors: [message.style.styleColor, message.style.styleColor.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: message.style.styleColor.opacity(0.6), radius: 24, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .messageCard(style: message.style, tier: .ready)
    }
}

// MARK: - Revealed Received Card

private struct RevealedReceivedCard: View {
    let message: DelayedMessage
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                MessageAvatar(name: message.senderName, style: message.style, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(message.senderName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(String(format: LS("inbox.card.sent_at"), message.sentAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fgMuted)
                    Text(String(format: LS("inbox.card.total_countdown"), shortDuration(TimeInterval(message.delaySeconds))))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fgMuted)
                    HStack(spacing: 4) {
                        Image(systemName: "lock").font(.system(size: 11))
                        Text(String(format: LS("inbox.card.opened_at"), message.unlockAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.fgMuted)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(isExpanded ? LS("inbox.card.hide") : LS("inbox.card.show")) { isExpanded.toggle() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentMint)
                        .buttonStyle(.plain)
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label(LS("common.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .transaction { $0.animation = nil }

            ExpandableMessageBody(text: message.body, isExpanded: isExpanded, includesDivider: false)
        }
        .padding(16)
        .messageCard(style: message.style, tier: .opened)
        .contentShape(RoundedRectangle(cornerRadius: cardRadius))
        .onTapGesture { isExpanded.toggle() }
    }
}

// MARK: - Sent Card

private struct SentCard: View {
    let message: DelayedMessage
    let now: Date
    var onDelete: (() -> Void)? = nil
    @State private var isExpanded = false

    private var tier: GlowTier {
        if message.status == .revealed { return .opened }
        if message.unlockAt <= now { return .ready }
        return .countingDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                MessageAvatar(name: message.receiverName, style: message.style, size: 40, isReady: tier == .ready)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: LS("inbox.sent_card.to"), message.receiverName))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(String(format: LS("inbox.card.sent_at"), message.sentAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.system(size: 12)).foregroundStyle(Color.fgMuted)
                    Text(String(format: LS("inbox.card.total_countdown"), shortDuration(TimeInterval(message.delaySeconds))))
                        .font(.system(size: 12)).foregroundStyle(Color.fgMuted)
                }

                Spacer()

                if let onDelete {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label(LS("common.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, message.status == .revealed ? 12 : 20)
            .transaction { $0.animation = nil }

            sentBody
        }
        .padding(16)
        .messageCard(style: message.style, tier: tier)
        .contentShape(RoundedRectangle(cornerRadius: cardRadius))
        .onTapGesture { isExpanded.toggle() }
    }

    @ViewBuilder
    private var sentBody: some View {
        if message.status == .revealed {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "lock").font(.system(size: 11))
                    Text(String(format: LS("inbox.sent_card.opened_at"), message.unlockAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.fgMuted)
                Spacer()
                Button(isExpanded ? LS("inbox.card.hide") : LS("inbox.card.show")) { isExpanded.toggle() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentMint)
                    .buttonStyle(.plain)
            }
            .transaction { $0.animation = nil }
            ExpandableMessageBody(text: message.body, isExpanded: isExpanded)
        } else if message.unlockAt > now {
            VStack(spacing: 6) {
                L("inbox.card.unlock_countdown")
                    .font(.system(size: 11, weight: .semibold)).tracking(3).foregroundStyle(Color.fgMuted)
                Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(message.style.styleColor)
                    .shadow(color: message.style.styleColor.opacity(0.35), radius: 12, x: 0, y: 0)
                    .lineLimit(1)
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "lock").font(.caption)
                        Text(message.unlockAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    }
                    .foregroundStyle(Color.fgMuted)
                    Spacer()
                    Button(isExpanded ? LS("inbox.card.hide") : LS("inbox.card.show")) { isExpanded.toggle() }
                        .font(.caption).foregroundStyle(Color.accentMint).buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            ExpandableMessageBody(text: message.body, isExpanded: isExpanded)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(message.style.styleColor)
                L("inbox.sent_card.waiting")
                    .font(.subheadline).foregroundStyle(Color.fgMuted)
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open").font(.caption)
                        Text(message.unlockAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    }
                    .foregroundStyle(Color.fgMuted)
                    Spacer()
                    Button(isExpanded ? LS("inbox.card.hide") : LS("inbox.card.show")) { isExpanded.toggle() }
                        .font(.caption).foregroundStyle(Color.accentMint).buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            ExpandableMessageBody(text: message.body, isExpanded: isExpanded)
        }
    }
}

// MARK: - Expandable Body

private struct ExpandableMessageBody: View {
    let text: String
    let isExpanded: Bool
    var includesDivider = true

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if includesDivider {
                        Divider().opacity(0.15).padding(.top, 2)
                    }
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, includesDivider ? 8 : 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isExpanded)
    }
}

// MARK: - Section Headers

private struct ReadyToOpenHeader: View {
    let count: Int
    let onComposeTapped: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            L("inbox.section.ready_to_open")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            if count > 0 {
                Text(String(format: LS("inbox.badge.new_count"), count))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.brandDark)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentMint)
                    .clipShape(Capsule())
            }
            Spacer()
            Button(action: onComposeTapped) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.pageBg)
                    .padding(6)
                    .background(Color.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

private struct CountingDownHeader: View {
    var body: some View {
        L("inbox.section.counting_down")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .textCase(nil)
            .padding(.vertical, 4)
    }
}

private struct InboxSectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        L(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .textCase(nil)
            .padding(.vertical, 4)
    }
}

// MARK: - Reveal Focus Overlay

private struct RevealFocusOverlay: View {
    let message: DelayedMessage
    let onDismiss: () -> Void

    @State private var scrimVisible = false
    @State private var bubbleVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(scrimVisible ? 0.70 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    MessageAvatar(name: message.senderName, style: message.style, size: 38, isReady: true)
                    VStack(alignment: .leading, spacing: 2) {
                        L("inbox.overlay.from")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(message.senderName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        Text(message.body)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                            .padding(.bottom, 18)
                    }
                    .frame(maxHeight: 280)

                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundStyle(.white.opacity(0.08))

                    HStack(spacing: 6) {
                        Image(systemName: "lock").font(.system(size: 11))
                        Text(String(format: LS("inbox.overlay.unlocked_at"), message.unlockAt.formatted(date: .abbreviated, time: .shortened)))
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.cardBase.opacity(0.92))
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(
                                stops: [
                                    .init(color: message.style.styleColor.opacity(0.14), location: 0),
                                    .init(color: .clear, location: 0.7)
                                ],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(message.style.styleColor.opacity(0.55), lineWidth: 0.5)
                )
                .shadow(color: message.style.styleColor.opacity(0.55), radius: 40, x: 0, y: 0)
                .shadow(color: message.style.styleColor.opacity(0.75), radius: 80, x: 0, y: 0)
                .shadow(color: .black.opacity(0.6), radius: 60, x: 0, y: 20)
            }
            .padding(.horizontal, 16)
            .opacity(bubbleVisible ? 1 : 0)
            .offset(y: bubbleVisible ? 0 : 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { scrimVisible = true }
            withAnimation(.easeOut(duration: 1.2).delay(0.4)) { bubbleVisible = true }
        }
    }
}

// MARK: - Recipient Picker Sheet

private struct RecipientPickerSheet: View {
    let friends: [Friend]
    var isLoading: Bool = false
    let onSelect: (Friend) -> Void

    private func initials(for name: String) -> String {
        let w = name.split(separator: " ")
        return w.count >= 2
            ? "\(w[0].prefix(1))\(w[1].prefix(1))".uppercased()
            : String(name.prefix(2)).uppercased()
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && friends.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friends.isEmpty {
                    ContentUnavailableView {
                        Label(LS("compose.pick_recipient.empty_title"), systemImage: "person.2")
                    } description: {
                        L("compose.pick_recipient.empty_description")
                    }
                } else {
                    List(friends) { friend in
                        Button {
                            onSelect(friend)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(Color.surfaceMid)
                                    Text(initials(for: friend.displayName))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                .frame(width: 40, height: 40)
                                Text(friend.displayName)
                                    .foregroundStyle(.white)
                            }
                        }
                        .listRowBackground(Color.cardBg)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.pageBg)
            .navigationTitle(LS("compose.pick_recipient"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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
        DelayedMessage(
            senderID: UUID(), receiverID: userID,
            senderName: "Yuni", receiverName: "Me",
            body: "Just wanted to say I'm really glad we're friends. That's it.",
            style: .heart,
            sentAt: Date().addingTimeInterval(-86400),
            unlockAt: Date().addingTimeInterval(-60),
            delaySeconds: 86340,
            status: .readyToReveal
        ),
        DelayedMessage(
            senderID: UUID(), receiverID: userID,
            senderName: "Nong", receiverName: "Me",
            body: "I've been thinking about this for a while and wanted to put it into words before I forgot. You've been a really steady presence in my life lately, even when you probably didn't realize it. The small things you do — checking in, showing up, being consistent — they matter more than you know. I hope things are going well for you right now, and if they're not, I'm here.",
            style: .cool,
            sentAt: Date().addingTimeInterval(-7200),
            unlockAt: Date().addingTimeInterval(-30),
            delaySeconds: 7170,
            status: .readyToReveal
        ),
        DelayedMessage(
            senderID: UUID(), receiverID: userID,
            senderName: "Alex", receiverName: "Me",
            body: "I've been meaning to write this for a while. There have been a lot of changes lately, and honestly it's been hard to keep up with everything. But every time things get overwhelming, I think about the people who genuinely make a difference — and you're one of them.\n\nYou might not notice it, but the way you treat the people around you is something a lot of others could learn from. You're patient, you listen, and you show up. I don't say that enough, so I wanted to make sure I said it now.\n\nHope this finds you well.",
            style: .warm,
            sentAt: Date().addingTimeInterval(-3600),
            unlockAt: Date().addingTimeInterval(-10),
            delaySeconds: 3590,
            status: .readyToReveal
        ),
    ]

    @State private var focusedMessage: DelayedMessage? = nil

    var body: some View {
        ZStack {
            Color.pageBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Self.fakeMessages) { message in
                        ReadyToOpenCard(
                            message: message,
                            now: Date(),
                            onOpenTapped: { focusedMessage = message }
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 16)
            }
        }
        .overlay {
            if let msg = focusedMessage {
                RevealFocusOverlay(message: msg) { focusedMessage = nil }
                    .ignoresSafeArea()
            }
        }
    }
}
#endif
