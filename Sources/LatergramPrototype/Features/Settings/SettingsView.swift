#if os(iOS)
import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

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

            if store.me.isPremium {
                Section(LS("settings.section_subscription")) {
                    Link(destination: manageSubscriptionsURL) {
                        Label(LS("settings.manage_subscription"), systemImage: "creditcard")
                    }
                }
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
    }
}
#endif
