#if os(iOS)
import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        ZStack {
            Color.pageBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // 略過：右上角全程可見
                Button(LS("onboarding.skip")) { store.send(.skipTapped) }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
                    .padding(.top, 12)

                // 分頁：左右滑動 + 按鈕推進雙軌（方案 A）
                TabView(selection: Binding(
                    get: { store.currentPage },
                    set: { store.send(.pageChanged($0)) }
                )) {
                    ForEach(Array(OnboardingFeature.pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: store.currentPage)

                // 自繪分頁指示點（內建白點在深色底對比差且不能改色）
                HStack(spacing: 8) {
                    ForEach(OnboardingFeature.pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == store.currentPage ? Color.brand : Color.fgMuted.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeInOut, value: store.currentPage)
                .padding(.bottom, 28)

                // CTA：最後一頁變「開始使用」，其餘「下一步」
                Button {
                    store.send(.nextTapped)
                } label: {
                    Text(store.isLastPage ? LS("onboarding.start") : LS("onboarding.next"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.brandDark)
                        .frame(maxWidth: 300)
                        .frame(height: 52)
                        .background(Color.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Single page

private struct OnboardingPageView: View {
    let page: OnboardingFeature.Page

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 圖示 + 品牌光暈（呼應 Inbox 卡片 style.opacity(0.18) 的同源做法）
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 160, height: 160)
                Image(systemName: page.systemImage)
                    .font(.system(size: 62, weight: .regular))
                    .foregroundStyle(Color.brand)
            }
            .padding(.bottom, 48)

            onboardingText(page.titleKey)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 16)

            onboardingText(page.subtitleKey)
                .font(.system(size: 19))
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// L() 的動態 key 版：頁面 key 存在 Page struct 裡、非字面量，
/// 需明確指定 Bundle.module 才能查到字串（CLAUDE.md #5）。
private func onboardingText(_ key: String) -> Text {
    Text(LocalizedStringKey(key), bundle: .module)
}
#endif
