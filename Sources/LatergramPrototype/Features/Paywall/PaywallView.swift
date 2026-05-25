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
                        featureRow(icon: "clock.badge.checkmark", text: LS("paywall.feature_long_delay"))
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Price + subscribe
                    VStack(spacing: 12) {
                        if store.isLoading {
                            ProgressView()
                                .frame(height: 50)
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
                        .disabled(store.isPurchasing || store.isRestoring)
                    }
                    .padding(.horizontal)
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
}

#endif
