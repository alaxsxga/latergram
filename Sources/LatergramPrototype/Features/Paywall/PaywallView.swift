#if os(iOS)
import ComposableArchitecture
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Bindable var store: StoreOf<PaywallFeature>

    // 購買/還原進行中時鎖住 sheet，避免 user 在 Apple sheet 結束→backend verify 完成
    // 之間的窗口關掉 paywall（@Presents dismiss 會 cancel effect，雖然 listener 仍會
    // 補上 entitlement，但 user 體感是「失敗了」會重複點購買）
    private var isProcessing: Bool {
        store.isPurchasing || store.isRestoring
    }

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
                        .foregroundStyle(isProcessing ? Color.secondary.opacity(0.4) : .secondary)
                }
                .disabled(isProcessing)
                .padding([.top, .trailing])
            }

            GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // Icon + title
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.primary)

                        L("paywall.title")
                            .font(.title2.bold())
                    }
                    .padding(.top, 8)

                    // Feature list
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow(icon: "clock.badge.checkmark", text: LS("paywall.feature_extended_delay"))
                        featureRow(icon: "bubble.left.and.bubble.right.fill", text: LS("paywall.feature_per_friend_limit"))
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

                        if isProcessing {
                            L("paywall.processing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 40)

                    // Restore + auto-renewal disclosure + legal links (required by App Review)
                    VStack(spacing: 12) {
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
                }
                .padding(.bottom, 24)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            }
        }
        .onAppear { store.send(.onAppear) }
        .interactiveDismissDisabled(isProcessing)
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
