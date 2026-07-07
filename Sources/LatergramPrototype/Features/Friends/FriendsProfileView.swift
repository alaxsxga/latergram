#if os(iOS)
import ComposableArchitecture
import LatergramCore
import SwiftUI
import UIKit


struct FriendsProfileView: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @State private var showInviteSheet = false

    @State private var selectedFriend: Friend? = nil

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            ScrollView {
                VStack(spacing: 20) {
                    profileCard
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            L("friends.section_header")
                                .font(.headline)
                            if !store.friends.isEmpty {
                                Text(String(format: LS("friends.count"), store.friends.count))
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
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showInviteSheet = true } label: {
                        ZStack {
                            Circle().fill(Color.brand).frame(width: 36, height: 36)
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.send(.settingsButtonTapped)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color.surfaceMid)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear { store.send(.onAppear) }
            .overlay {
                if store.isLoading && store.friends.isEmpty {
                    ProgressView()
                }
            }
            .alert(
                L("friends.delete_friend_title"),
                isPresented: Binding(
                    get: { store.friendPendingDeletion != nil },
                    set: { if !$0 { store.send(.removeFriendCancelled) } }
                ),
                presenting: store.friendPendingDeletion
            ) { friend in
                Button(LS("friends.delete_confirm_button"), role: .destructive) {
                    store.send(.removeFriendConfirmed)
                }
                Button(LS("common.cancel"), role: .cancel) {}
            } message: { friend in
                Text(String(format: LS("friends.delete_confirm_message"), friend.displayName))
            }
            .alert(
                store.inviteAcceptError == .alreadyFriends ? L("friends.already_friends_title") : L("friends.add_failed_title"),
                isPresented: Binding(
                    get: { store.inviteAcceptError != nil },
                    set: { if !$0 { store.send(.inviteAcceptErrorDismissed) } }
                ),
                presenting: store.inviteAcceptError
            ) { _ in
                Button(LS("common.ok"), role: .cancel) { store.send(.inviteAcceptErrorDismissed) }
            } message: { failure in
                if failure != .alreadyFriends {
                    Text(failure.message)
                }
            }
            // Success alert for the deep-link accept flow (invite sheet closed).
            // The paste-in-sheet flow shows the same alert inside InviteSheet;
            // the showInviteSheet guard keeps the two from presenting together.
            .alert(
                Text(String(format: LS("friends.invite_accepted_title"), store.inviteAcceptedFriendName ?? "")),
                isPresented: Binding(
                    get: { store.inviteAcceptedFriendName != nil && !showInviteSheet },
                    set: { if !$0 { store.send(.inviteAcceptedAlertDismissed) } }
                )
            ) {
                Button(LS("common.ok"), role: .cancel) { store.send(.inviteAcceptedAlertDismissed) }
            }
            .alert(L("friends.invite_pasted_title"), isPresented: Binding(
                get: { store.showDeepLinkInviteAlert },
                set: { if !$0 { store.send(.deepLinkAlertDismissed) } }
            )) {
                Button(LS("friends.invite_send_button")) { store.send(.acceptInviteCodeTapped) }
                Button(LS("friends.invite_later_button"), role: .cancel) { store.send(.deepLinkAlertDismissed) }
            } message: {
                Text(String(format: LS("friends.invite_confirm_message"), store.pastedInviteCode))
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
            .sheet(item: $selectedFriend) { friend in
                FriendActionSheet(
                    friend: friend,
                    onSendMessage: {
                        selectedFriend = nil
                        store.send(.friendTapped(friend))
                    },
                    onDelete: {
                        selectedFriend = nil
                        store.send(.removeFriendSwiped(friend))
                    }
                )
                .presentationDetents([.height(284)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.pageBg.opacity(0.35))
            }
            .sheet(item: $store.scope(state: \.compose, action: \.compose)) { composeStore in
                ComposeView(store: composeStore)
            }
        } destination: { settingsStore in
            SettingsView(store: settingsStore)
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
        .cardStyle(radius: 20)
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
                        selectedFriend = friend
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .cardStyle()
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            L("friends.empty_title")
                .font(.subheadline.bold())
            L("friends.empty_description")
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                InitialsAvatar(name: friend.displayName, size: 44)

                Text(friend.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Invite Sheet

private struct InviteSheet: View {
    @Bindable var store: StoreOf<FriendsFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var didCopyCode = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    L("friends.invite_sheet.title")
                        .font(.title2.bold())
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color(white: 0.22))
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
        .pageBackground()
        .alert(
            Text(String(format: LS("friends.invite_accepted_title"), store.inviteAcceptedFriendName ?? "")),
            isPresented: Binding(
                get: { store.inviteAcceptedFriendName != nil },
                set: { if !$0 { store.send(.inviteAcceptedAlertDismissed) } }
            )
        ) {
            Button(LS("common.ok"), role: .cancel) {
                store.send(.inviteAcceptedAlertDismissed)
                dismiss()
            }
        }
    }

    // MARK: My Code

    private var myCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                L("friends.invite_sheet.my_code")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                if !store.generatedInviteCode.isEmpty {
                    Button(role: .destructive) {
                        store.send(.revokeInviteCodeTapped)
                    } label: {
                        Label(LS("friends.invite_sheet.revoke"), systemImage: "arrow.counterclockwise")
                            .font(.caption.bold())
                            .font(.caption.bold())
                    }
                }
            }

            if store.generatedInviteCode.isEmpty {
                Button {
                    store.send(.generateInviteCodeTapped)
                } label: {
                    L("friends.invite_sheet.generate")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                VStack(spacing: 14) {
                    Text(store.generatedInviteCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.brand)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                        .cardBackground(radius: 16)

                    Button {
                        store.send(.shareInviteCodeTapped)
                    } label: {
                        Label(LS("friends.invite_sheet.share"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        UIPasteboard.general.string = store.generatedInviteCode
                        store.send(.copyInviteCodeTapped)
                        withAnimation { didCopyCode = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            withAnimation { didCopyCode = false }
                        }
                    } label: {
                        Label {
                            Text(didCopyCode ? LS("friends.invite_sheet.copied") : LS("friends.invite_sheet.copy_code"))
                        } icon: {
                            Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                                .frame(height: 18)
                        }
                        .font(.headline)
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.surfaceMid)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(didCopyCode)
                }
            }
        }
    }

    // MARK: Divider

    private var orDivider: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(Color(white: 0.25))
    }

    // MARK: Enter Code

    private var enterCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            L("friends.invite_sheet.add_friend_title")
                .font(.title2.bold())

            HStack(spacing: 10) {
                TextField(LS("friends.invite_sheet.paste_placeholder"), text: $store.pastedInviteCode)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .cardBackground()

                let canJoin = !store.pastedInviteCode
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    store.send(.acceptInviteCodeTapped)
                } label: {
                    L("friends.invite_sheet.add_button")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(canJoin ? Color.brand : Color.brand.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canJoin)
            }
        }
    }
}

// MARK: - Friend Action Sheet

private struct FriendActionSheet: View {
    let friend: Friend
    let onSendMessage: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                InitialsAvatar(name: friend.displayName, size: 52)
                Text(friend.displayName)
                    .font(.headline)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            Divider()

            VStack(spacing: 0) {
                actionButton(
                    icon: "paperplane.fill",
                    label: LS("friends.send_message"),
                    color: .brand,
                    action: onSendMessage
                )

                // 「編輯頭像」暫時隱藏，等大頭照功能（post-MVP）完成後再加回

                Divider().padding(.leading, 56)

                actionButton(
                    icon: "person.fill.xmark",
                    label: LS("friends.delete_friend_menu"),
                    color: .red,
                    action: onDelete
                )
            }
        }
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(label)
                    .foregroundStyle(color == .secondary ? Color.primary : color)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Initials Avatar

struct InitialsAvatar: View {
    let name: String
    let size: CGFloat

    private var avatarColor: Color {
        // String.hashValue is randomized per launch; use stable scalar sum instead
        let stableHash = name.unicodeScalars.enumerated().reduce(0) {
            $0 &+ Int($1.element.value) &* (31 &* ($1.offset + 1))
        }
        return Color.avatarPalette[abs(stableHash) % Color.avatarPalette.count]
    }

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Circle()
            .fill(avatarColor)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
#endif
