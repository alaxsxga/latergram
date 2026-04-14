import ComposableArchitecture
import LatergramCore
import SwiftUI

private let pageBg = Color(.systemGroupedBackground)

struct FriendsProfileView: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @State private var showInviteSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("好友")
                                .font(.headline)
                            if !store.friends.isEmpty {
                                Text("\(store.friends.count)人")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        friendsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(pageBg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInviteSheet = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            store.send(.logoutConfirmTapped)
                        } label: {
                            Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear { store.send(.onAppear) }
            .overlay {
                if store.isLoading && store.friends.isEmpty {
                    ProgressView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let banner = store.banner {
                    Text(banner)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
            .alert("確定要登出嗎？", isPresented: Binding(
                get: { store.isConfirmingLogout },
                set: { if !$0 { store.send(.logoutCancelled) } }
            )) {
                Button("登出", role: .destructive) { store.send(.logoutTapped) }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "刪除好友",
                isPresented: Binding(
                    get: { store.friendPendingDeletion != nil },
                    set: { if !$0 { store.send(.removeFriendCancelled) } }
                ),
                presenting: store.friendPendingDeletion
            ) { friend in
                Button("刪除 \(friend.displayName)", role: .destructive) {
                    store.send(.removeFriendConfirmed)
                }
                Button("取消", role: .cancel) {}
            } message: { friend in
                Text("確定要刪除 \(friend.displayName)？此操作無法復原。")
            }
            .alert(
                Text(store.inviteAcceptError == .alreadyFriends ? "已經是好友" : "無法加入好友"),
                isPresented: Binding(
                    get: { store.inviteAcceptError != nil },
                    set: { if !$0 { store.send(.inviteAcceptErrorDismissed) } }
                ),
                presenting: store.inviteAcceptError
            ) { _ in
                Button("確定", role: .cancel) { store.send(.inviteAcceptErrorDismissed) }
            } message: { failure in
                if failure != .alreadyFriends {
                    Text(failure.message)
                }
            }
            .alert("邀請碼已貼上", isPresented: Binding(
                get: { store.showDeepLinkInviteAlert },
                set: { if !$0 { store.send(.deepLinkAlertDismissed) } }
            )) {
                Button("送出邀請") { store.send(.acceptInviteCodeTapped) }
                Button("稍後再說", role: .cancel) { store.send(.deepLinkAlertDismissed) }
            } message: {
                Text("邀請碼 \(store.pastedInviteCode) 已填入，要立即加對方為好友嗎？")
            }
            .sheet(isPresented: Binding(
                get: { store.isSharingInvite },
                set: { if !$0 { store.send(.shareSheetDismissed) } }
            )) {
                ShareSheet(items: [store.inviteShareMessage])
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteSheet(store: store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 8) {
            InitialsAvatar(name: store.me.displayName, size: 52)
            Text(store.me.displayName)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Friends Card

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.friends.isEmpty && !store.isLoading {
                emptyFriendsState
            } else {
                ForEach(Array(store.friends.enumerated()), id: \.element.id) { index, friend in
                    if index > 0 {
                        Divider().padding(.leading, 72)
                    }
                    FriendRow(friend: friend) {
                        store.send(.removeFriendSwiped(friend))
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 1)
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("還沒有好友")
                .font(.subheadline.bold())
            Text("點右上角邀請朋友加入")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Friend Row

private struct FriendRow: View {
    let friend: Friend
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: friend.displayName, size: 44)

            Text(friend.displayName)
                .font(.body)

            Spacer()

            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("刪除好友", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Invite Sheet

private struct InviteSheet: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("邀請好友")
                        .font(.title2.bold())
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 28)

            ScrollView {
                VStack(spacing: 28) {
                    myCodeSection
                    orDivider
                    enterCodeSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: My Code

    private var myCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的邀請碼")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                if !store.generatedInviteCode.isEmpty {
                    Button(role: .destructive) {
                        store.send(.revokeInviteCodeTapped)
                    } label: {
                        Label("讓失效", systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                            .font(.caption.bold())
                    }
                }
            }

            if store.generatedInviteCode.isEmpty {
                Button {
                    store.send(.generateInviteCodeTapped)
                } label: {
                    Text("產生邀請碼")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                VStack(spacing: 14) {
                    Text(store.generatedInviteCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button {
                        store.send(.shareInviteCodeTapped)
                    } label: {
                        Label("分享邀請碼", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: Divider

    private var orDivider: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(Color(.systemGray4))
    }

    // MARK: Enter Code

    private var enterCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加入好友")
                .font(.title2.bold())

            HStack(spacing: 10) {
                TextField("貼上朋友的邀請碼", text: $store.pastedInviteCode)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                let canJoin = !store.pastedInviteCode
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    store.send(.acceptInviteCodeTapped)
                } label: {
                    Text("加入")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(canJoin ? Color.accentColor : Color.accentColor.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canJoin)
            }
        }
    }
}

// MARK: - Initials Avatar

private struct InitialsAvatar: View {
    let name: String
    let size: CGFloat

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }
}
