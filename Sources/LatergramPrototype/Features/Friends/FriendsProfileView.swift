import ComposableArchitecture
import LatergramCore
import SwiftUI

struct FriendsProfileView: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            List {
                profileSection
                inviteSection
                friendsSection
            }
            .navigationTitle("好友與個人")
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
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section("個人") {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.me.displayName).font(.headline)
                Text("@\(store.me.username)").foregroundStyle(.secondary)
            }
            Button("登出", role: .destructive) {
                store.send(.logoutConfirmTapped)
            }
            .alert("確定要登出嗎？", isPresented: Binding(
                get: { store.isConfirmingLogout },
                set: { if !$0 { store.send(.logoutCancelled) } }
            )) {
                Button("登出", role: .destructive) { store.send(.logoutTapped) }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var inviteSection: some View {
        Section("邀請好友") {
            HStack {
                TextField("貼上邀請碼", text: $store.pastedInviteCode)
                    .autocorrectionDisabled()
                Button("接受") { store.send(.acceptInviteCodeTapped) }
                    .disabled(store.pastedInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.generatedInviteCode.isEmpty {
                Button("產生邀請碼") { store.send(.generateInviteCodeTapped) }
            } else {
                Text(store.generatedInviteCode).monospaced()
                Button {
                    UIPasteboard.general.string = store.generatedInviteCode
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "已複製" : "複製邀請碼",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(didCopy ? .green : .accentColor)
                }
                Button("分享邀請碼") { store.send(.shareInviteCodeTapped) }
                Button("讓邀請碼失效", role: .destructive) { store.send(.revokeInviteCodeTapped) }
            }
        }
    }

    private var friendsSection: some View {
        Section("好友") {
            if store.friends.isEmpty && !store.isLoading {
                Text("尚無好友，快邀請朋友加入！")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.friends) { friend in
                    HStack {
                        Text(friend.displayName)
                        Spacer()
                        Text(friend.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(friend.status == .accepted ? .green : .orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.send(.removeFriendSwiped(friend))
                        } label: {
                            Label("刪除", systemImage: "person.fill.xmark")
                        }
                    }
                }
            }
        }
    }
}
