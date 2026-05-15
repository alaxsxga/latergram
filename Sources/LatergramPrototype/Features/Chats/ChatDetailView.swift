import ComposableArchitecture
import LatergramCore
import SwiftUI

// MARK: - Spec colors (chat history screen only)

private let specBgPage   = Color(red: 0.051, green: 0.067, blue: 0.090) // #0D1117
private let specBgOpened = Color(red: 0.051, green: 0.110, blue: 0.090) // #0D1C17
private let specBgActive = Color(red: 0.078, green: 0.106, blue: 0.176) // #141B2D
private let specTextDark = Color(red: 0.039, green: 0.055, blue: 0.090) // #0A0E17

struct ChatDetailView: View {
    @Bindable var store: StoreOf<ChatDetailFeature>

    var body: some View {
        Group {
            if store.isLoading && store.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.messages.isEmpty {
                ContentUnavailableView {
                    Label(LS("chat_detail.empty_title"), systemImage: "bubble.left")
                } description: {
                    L("chat_detail.empty_description")
                }
            } else {
                messageList
            }
        }
        .navigationTitle(store.friend.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.send(.composeTapped) } label: {
                    if store.isAtSendLimit, let unlockAt = store.earliestBlockedUnlockAt {
                        Label(CountdownFormatter.dHms(from: unlockAt.timeIntervalSince(store.now)),
                              systemImage: "clock")
                    } else {
                        L("chat_detail.create_button")
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
        .alert(L("common.error_title"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.send(.errorDismissed) } }
        )) {
            Button(LS("common.ok"), role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(specBgPage)
            .onAppear {
                if let last = store.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
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
                L("chat_detail.limit_info")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    // TODO: IAP — 導向購買頁
                    onDismiss()
                } label: {
                    Label(LS("chat_detail.unlock_more"), systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(LS("chat_detail.got_it"), action: onDismiss)
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

    @State private var isExpanded = false

    private var effectiveStatus: MessageStatus {
        message.status == .scheduled && message.unlockAt <= now ? .readyToReveal : message.status
    }

    private var bubbleBg: Color {
        switch effectiveStatus {
        case .revealed:      specBgOpened
        case .readyToReveal: specBgActive
        case .scheduled:     .brand
        }
    }

    private var showBorder: Bool { effectiveStatus == .readyToReveal }

    private var bubbleShape: UnevenRoundedRectangle {
        isMine
            ? UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                     bottomTrailingRadius: 4, topTrailingRadius: 18)
            : UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4,
                                     bottomTrailingRadius: 18, topTrailingRadius: 18)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 60) }
            if !isMine {
                ChatBubbleAvatar(name: message.senderName)
                    .padding(.trailing, 6)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(12)
                    .background(bubbleBg)
                    .clipShape(bubbleShape)
                    .overlay {
                        if showBorder {
                            bubbleShape.stroke(Color.brand, lineWidth: 1.5)
                        }
                    }
                    .contentShape(bubbleShape)
                    .onTapGesture { handleTap() }
                    .contextMenu {
                        if let onDelete {
                            Button(role: .destructive) { onDelete() } label: {
                                Label(LS("chat_detail.delete_message"), systemImage: "trash")
                            }
                        }
                    }

                Text(message.sentAt.formatted(
                    .dateTime.month(.abbreviated).day()
                             .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                ))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, isMine ? 0 : 2)
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }

    private func handleTap() {
        guard effectiveStatus != .scheduled else { return }
        isExpanded.toggle()
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 0) {
            if isMine { sentContent } else { receivedContent }
            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.12))
                    .padding(.vertical, 8)
                expandedTimeInfo
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isExpanded)
    }

    @ViewBuilder
    private var expandedTimeInfo: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(CountdownFormatter.dHms(from: TimeInterval(message.delaySeconds)))
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(message.unlockAt.formatted(
                    .dateTime.month(.abbreviated).day()
                             .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                ))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.55))
    }

    @ViewBuilder
    private var sentContent: some View {
        switch effectiveStatus {
        case .revealed:
            Text(message.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))

        case .scheduled:
            VStack(alignment: .trailing, spacing: 8) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(specTextDark)
                HStack(spacing: 6) {
                    ClockCircleIcon(size: 16,
                                    bgColor: .black.opacity(0.12),
                                    handColor: .black.opacity(0.4))
                    Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }

        case .readyToReveal:
            VStack(alignment: .trailing, spacing: 6) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.88))
                HStack(spacing: 4) {
                    ClockCircleIcon(size: 16, bgColor: .brand, handColor: specTextDark)
                    L("chat_detail.badge.unread")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.brand)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.brand.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var receivedContent: some View {
        switch effectiveStatus {
        case .revealed:
            Text(message.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))

        case .scheduled:
            HStack(spacing: 8) {
                ClockCircleIcon(size: 26,
                                bgColor: .black.opacity(0.12),
                                handColor: .black.opacity(0.4))
                Text(CountdownFormatter.dHms(from: message.unlockAt.timeIntervalSince(now)))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black.opacity(0.55))
            }

        case .readyToReveal:
            HStack(spacing: 8) {
                ClockCircleIcon(size: 28, bgColor: .brand, handColor: specTextDark)
                L("chat_detail.badge.not_yet_opened")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
        }
    }
}

// MARK: - Clock Circle Icon

private struct ClockCircleIcon: View {
    let size: CGFloat
    let bgColor: Color
    let handColor: Color

    var body: some View {
        ZStack {
            Circle().fill(bgColor)
            Image(systemName: "clock")
                .font(.system(size: size * 0.55))
                .foregroundStyle(handColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Chat Bubble Avatar

private struct ChatBubbleAvatar: View {
    let name: String
    private static let bg = Color(red: 0.118, green: 0.157, blue: 0.267) // #1E2844

    var body: some View {
        ZStack {
            Circle().fill(Self.bg)
            Text(initials)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.brand)
        }
        .frame(width: 26, height: 26)
    }

    private var initials: String {
        let w = name.split(separator: " ")
        return w.count >= 2
            ? "\(w[0].prefix(1))\(w[1].prefix(1))".uppercased()
            : String(name.prefix(2)).uppercased()
    }
}
