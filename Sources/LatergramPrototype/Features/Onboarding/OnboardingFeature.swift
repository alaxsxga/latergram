import ComposableArchitecture
import Foundation

/// 首次啟用引導。三頁概念說明（封存 → 等待解封 → 玩法），可略過。
/// 是否看過的旗標由 AppFeature 以 device 層級 UserDefaults 持久化，
/// 不隨登出清除（CLAUDE.md #1 的 clean slate 只清 user 狀態，引導是裝置層級）。
@Reducer
struct OnboardingFeature {
    /// 一頁的內容。新增／調整頁面時改這個 static 陣列即可（CLAUDE.md #4：預留擴充），
    /// key 對應 xcstrings 的 onboarding.pageN.*。
    struct Page: Equatable, Identifiable {
        let id: Int
        let systemImage: String
        let titleKey: String
        let subtitleKey: String
    }

    static let pages: [Page] = [
        Page(id: 0, systemImage: "envelope.fill",
             titleKey: "onboarding.page1.title", subtitleKey: "onboarding.page1.subtitle"),
        Page(id: 1, systemImage: "hourglass",
             titleKey: "onboarding.page2.title", subtitleKey: "onboarding.page2.subtitle"),
        Page(id: 2, systemImage: "sparkles",
             titleKey: "onboarding.page3.title", subtitleKey: "onboarding.page3.subtitle"),
    ]

    @ObservableState
    struct State: Equatable {
        var currentPage: Int = 0
        var isLastPage: Bool { currentPage >= OnboardingFeature.pages.count - 1 }
    }

    enum Action {
        case pageChanged(Int)
        case nextTapped
        case skipTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// 略過或走完最後一頁都送這個；AppFeature 收到後寫旗標並關閉。
            case finished
        }
    }

    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .pageChanged(page):
                state.currentPage = page
                return .none

            case .nextTapped:
                guard state.isLastPage else {
                    state.currentPage += 1
                    return .none
                }
                return .send(.delegate(.finished))

            case .skipTapped:
                sentryClient.addBreadcrumb(category: "onboarding", message: "onboarding.skipped")
                return .send(.delegate(.finished))

            case .delegate:
                return .none
            }
        }
    }
}
