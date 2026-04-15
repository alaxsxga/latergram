import ComposableArchitecture
import LatergramCore
import SwiftUI

// MARK: - Preview helpers (remove after visual review)

#if DEBUG
private let previewMe = UUID()
private let previewFriends: [Friend] = [
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Alice",   status: .accepted),
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Bob",     status: .accepted),
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, displayName: "Carol",   status: .accepted),
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, displayName: "Dave",    status: .accepted),
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, displayName: "Eve",     status: .accepted),
    Friend(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, displayName: "Frank",   status: .accepted),
]
private let previewMessages: [UUID: DelayedMessage] = {
    let alice = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let bob   = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let carol = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let dave  = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let eve   = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let frank = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    return [
        // 收到：倒數中
        alice: DelayedMessage(senderID: alice, receiverID: previewMe, senderName: "Alice", receiverName: "Me",
                              body: "神秘訊息", style: .classic, unlockAt: Date().addingTimeInterval(86400 * 2), status: .scheduled),
        // 收到：可以開啟了
        bob: DelayedMessage(senderID: bob, receiverID: previewMe, senderName: "Bob", receiverName: "Me",
                            body: "神秘訊息", style: .warm, unlockAt: Date().addingTimeInterval(-60), status: .scheduled),
        // 收到：已開啟
        carol: DelayedMessage(senderID: carol, receiverID: previewMe, senderName: "Carol", receiverName: "Me",
                              body: "今天天氣真好，你有出門嗎？", style: .cool, unlockAt: Date().addingTimeInterval(-3600), status: .revealed),
        // 發送：倒數中
        dave: DelayedMessage(senderID: previewMe, receiverID: dave, senderName: "Me", receiverName: "Dave",
                             body: "記得帶傘，下午會下雨", style: .classic, unlockAt: Date().addingTimeInterval(86400 * 5), status: .scheduled),
        // 發送：等待開啟
        eve: DelayedMessage(senderID: previewMe, receiverID: eve, senderName: "Me", receiverName: "Eve",
                            body: "生日快樂！這是給你的驚喜", style: .heart, unlockAt: Date().addingTimeInterval(-3600), status: .scheduled),
        // 發送：對方已開啟
        frank: DelayedMessage(senderID: previewMe, receiverID: frank, senderName: "Me", receiverName: "Frank",
                              body: "週末要不要一起爬山？", style: .classic, unlockAt: Date().addingTimeInterval(-7200), status: .revealed),
    ]
}()

#Preview {
    var state = ChatsFeature.State()
    state.currentUserID = previewMe
    state.friends = IdentifiedArray(uniqueElements: previewFriends)
    state.latestMessages = previewMessages
    return ChatsView(store: Store(initialState: state) { ChatsFeature() })
}
#endif

private let pageBg = Color(.systemGroupedBackground)

struct ChatsView: View {
    @Bindable var store: StoreOf<ChatsFeature>

    private var friendsWithMessages: [Friend] {
        store.friends.elements.filter { store.latestMessages[$0.id] != nil }
    }

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            Group {
                if store.isLoading && store.friends.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if friendsWithMessages.isEmpty {
                    ContentUnavailableView(
                        "沒有往來訊息",
                        systemImage: "tray",
                        description: Text("從信箱頁發送或接收訊息後就會出現")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(friendsWithMessages.enumerated()), id: \.element.id) { index, friend in
                                if index > 0 {
                                    Divider().padding(.leading, 72)
                                }
                                Button {
                                    store.send(.friendTapped(friend))
                                } label: {
                                    ChatRow(
                                        friend: friend,
                                        message: store.latestMessages[friend.id]!,
                                        currentUserID: store.currentUserID
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                    .background(pageBg)
                }
            }
            .navigationTitle("")
            .onAppear { store.send(.onAppear) }
        } destination: { chatStore in
            ChatDetailView(store: chatStore)
        }
    }
}

// MARK: - Chat Row

private struct ChatRow: View {
    let friend: Friend
    let message: DelayedMessage
    let currentUserID: UUID

    private var isSent: Bool { message.senderID == currentUserID }

    private var effectiveStatus: MessageStatus {
        if message.status == .scheduled && message.unlockAt <= Date() {
            return .readyToReveal
        }
        return message.status
    }

    private var previewText: String {
        if isSent {
            return message.body
        }
        switch effectiveStatus {
        case .scheduled:     return "新訊息倒數中"
        case .readyToReveal: return "有新訊息可開啟"
        case .revealed:      return message.body
        }
    }

    private var statusIcon: (name: String, color: Color)? {
        switch effectiveStatus {
        case .scheduled:     return ("clock.circle.fill", Color(.systemGray))
        case .readyToReveal: return ("clock.circle.fill", Color(red: 0.6, green: 0.85, blue: 0.6))
        case .revealed:      return nil
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: friend.displayName, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.body)

                HStack(spacing: 4) {
                    Image(systemName: isSent ? "paperplane" : "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let icon = statusIcon {
                Image(systemName: icon.name)
                    .font(.system(size: 18))
                    .foregroundStyle(icon.color)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
