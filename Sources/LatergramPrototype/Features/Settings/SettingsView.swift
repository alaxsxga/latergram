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
        }
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
        .sheet(item: $store.scope(state: \.paywall, action: \.paywall)) {
            PaywallView(store: $0)
        }
    }
}
#endif
