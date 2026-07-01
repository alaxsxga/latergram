#if os(iOS)
import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        Form {
            Section(LS("settings.section_account")) {
                HStack {
                    InitialsAvatar(name: store.me.displayName, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.me.displayName)
                            .font(.headline)
                        Text(store.me.isPremium ? LS("settings.premium_status") : LS("settings.free_status"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                .padding(.vertical, 4)
            }

            Section(LS("settings.section_subscription")) {
                if store.me.isPremium {
                    Link(destination: manageSubscriptionsURL) {
                        Label(LS("settings.manage_subscription"), systemImage: "creditcard")
                    }
                } else {
                    Button {
                        store.send(.upgradeButtonTapped)
                    } label: {
                        Label(LS("settings.upgrade_to_premium"), systemImage: "crown.fill")
                    }
                }
            }

            Section {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label(LS("settings.language"), systemImage: "globe")
                }
            } header: {
                Text(LS("settings.section_general"))
            } footer: {
                Text(LS("settings.language_footer"))
            }

            Section(LS("settings.section_about")) {
                Button {
                    store.send(.feedbackButtonTapped)
                } label: {
                    Label(LS("feedback.title"), systemImage: "envelope")
                }
                Link(destination: LegalURLs.privacyPolicy) {
                    Label(LS("legal.privacy_policy"), systemImage: "hand.raised")
                }
                Link(destination: LegalURLs.termsOfUse) {
                    Label(LS("legal.terms_of_use"), systemImage: "doc.text")
                }
            }

            Section {
                Button(role: .destructive) {
                    store.send(.logoutConfirmTapped)
                } label: {
                    Label(LS("friends.logout_button"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    store.send(.deleteAccountConfirmTapped)
                } label: {
                    HStack {
                        Label(LS("settings.delete_account"), systemImage: "trash")
                        if store.isDeletingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
        }
        // 刪除進行中鎖住整頁，避免同時觸發登出等其他 session 操作互相打架
        .disabled(store.isDeletingAccount)
        .navigationTitle(LS("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert(L("friends.logout_confirm_title"), isPresented: Binding(
            get: { store.isConfirmingLogout },
            set: { if !$0 { store.send(.logoutCancelled) } }
        )) {
            Button(LS("friends.logout_button"), role: .destructive) { store.send(.logoutTapped) }
            Button(LS("common.cancel"), role: .cancel) {}
        }
        .alert(L("settings.delete_account_confirm_title"), isPresented: Binding(
            get: { store.isConfirmingDeleteAccount },
            set: { if !$0 { store.send(.deleteAccountCancelled) } }
        )) {
            Button(LS("settings.delete_account"), role: .destructive) { store.send(.deleteAccountTapped) }
            Button(LS("common.cancel"), role: .cancel) {}
        } message: {
            Text(LS("settings.delete_account_confirm_message"))
        }
        .alert($store.scope(state: \.deleteErrorAlert, action: \.deleteErrorAlert))
        .sheet(item: $store.scope(state: \.paywall, action: \.paywall)) {
            PaywallView(store: $0)
        }
        .sheet(item: $store.scope(state: \.feedback, action: \.feedback)) {
            FeedbackView(store: $0)
        }
        .alert($store.scope(state: \.thanksAlert, action: \.thanksAlert))
    }
}
#endif
