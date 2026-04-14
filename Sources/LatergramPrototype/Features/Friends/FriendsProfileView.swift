import ComposableArchitecture
import LatergramCore
import SwiftUI

private let pageBg = Color(.systemGroupedBackground)

struct FriendsProfileView: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @State private var didCopy = false
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
                InviteSheet(store: store, didCopy: $didCopy)
                    .presentationDetents([.large])
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
    @Binding var didCopy: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.generatedInviteCode.isEmpty {
                        Button("產生我的邀請碼") {
                            store.send(.generateInviteCodeTapped)
                        }
                    } else {
                        Text(store.generatedInviteCode)
                            .monospaced()
                            .foregroundStyle(.primary)

                        Button {
                            UIPasteboard.general.string = store.generatedInviteCode
                            didCopy = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                didCopy = false
                            }
                        } label: {
                            Label(
                                didCopy ? "已複製" : "複製邀請碼",
                                systemImage: didCopy ? "checkmark" : "doc.on.doc"
                            )
                            .foregroundStyle(didCopy ? .green : .accentColor)
                        }

                        Button("分享邀請碼") {
                            store.send(.shareInviteCodeTapped)
                        }

                        Button("讓邀請碼失效", role: .destructive) {
                            store.send(.revokeInviteCodeTapped)
                        }
                    }
                } header: {
                    Text("我的邀請碼")
                } footer: {
                    Text("將邀請碼傳給朋友，對方輸入後即可加你為好友。")
                }

                Section("輸入邀請碼") {
                    HStack {
                        TextField("貼上朋友的邀請碼", text: $store.pastedInviteCode)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                        Button("加入") {
                            store.send(.acceptInviteCodeTapped)
                        }
                        .disabled(
                            store.pastedInviteCode
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
            }
            .navigationTitle("邀請好友")
            .navigationBarTitleDisplayMode(.inline)
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
