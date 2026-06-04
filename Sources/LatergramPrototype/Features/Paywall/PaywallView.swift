#if os(iOS)
import ComposableArchitecture
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Bindable var store: StoreOf<PaywallFeature>

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button {
                    store.send(.dismissTapped)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding([.top, .trailing])
            }

            ScrollView {
                VStack(spacing: 24) {
                    // Icon + title
                    VStack(spacing: 12) {
                        Image(systemName: "hourglass.badge.plus")
                            .font(.system(size: 52))
                            .foregroundStyle(.primary)

                        L("paywall.title")
                            .font(.title2.bold())
                    }
                    .padding(.top, 8)

                    // Feature list
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow(icon: "clock.badge.checkmark", text: LS("paywall.feature_extended_delay"))
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Price + subscribe — verify 完成才顯示，避免引導已訂閱用戶重複購買
                    VStack(spacing: 12) {
                        if store.alreadyPremiumProfile != nil {
                            alreadyPremiumSection
                        } else if store.isVerifyingEntitlement {
                            HStack(spacing: 8) {
                                ProgressView()
                                L("paywall.verifying_entitlement")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 50)
                        } else if store.isLoading {
                            ProgressView()
                                .frame(height: 50)
                        } else if store.productsLoadFailed {
                            VStack(spacing: 8) {
                                L("paywall.load_failed")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button {
                                    store.send(.retryLoadProductsTapped)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        L("paywall.retry")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else if let product = store.products.first {
                            Button {
                                store.send(.purchaseTapped(product))
                            } label: {
                                HStack(spacing: 6) {
                                    if store.isPurchasing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        L("paywall.subscribe")
                                        Text(verbatim: "· \(product.displayPrice) / 月")
                                    }
                                }
                                .frame(maxWidth: .infinity  )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isPurchasing || store.isRestoring)
                        } else {
                            L("paywall.loading")
                                .foregroundStyle(.secondary)
                                .frame(height: 50)
                        }

                        if store.alreadyPremiumProfile == nil {
                            Button {
                                store.send(.restoreTapped)
                            } label: {
                                if store.isRestoring {
                                    ProgressView()
                                } else {
                                    L("paywall.restore")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                            .disabled(store.isPurchasing || store.isRestoring || store.isVerifyingEntitlement)
                        }
                    }
                    .padding(.horizontal)

                    // Auto-renewal disclosure + legal links (required by App Review)
                    VStack(spacing: 8) {
                        L("paywall.terms_disclosure")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Link(destination: LegalURLs.privacyPolicy) {
                                L("legal.privacy_policy")
                                    .font(.caption2)
                            }
                            Text(verbatim: "·")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Link(destination: LegalURLs.termsOfUse) {
                                L("legal.terms_of_use")
                                    .font(.caption2)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear { store.send(.onAppear) }
        .alert(
            LS("common.error_title"),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.errorDismissed) } }
            )
        ) {
            Button(LS("common.ok"), role: .cancel) { store.send(.errorDismissed) }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var alreadyPremiumSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                L("paywall.already_premium")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Link(destination: URL(string: "itms-apps://apps.apple.com/account/subscriptions")!) {
                L("paywall.manage_subscription")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button {
                store.send(.alreadyPremiumDismissTapped)
            } label: {
                L("paywall.done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#endif
