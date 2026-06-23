import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct FeedbackFeature {
    /// 回饋分類。新增類別時這裡加一個 case，並同步 migration 的 check 約束 +
    /// xcstrings 的 feedback.category_* 字串即可（CLAUDE.md：預留擴充）。
    enum Category: String, CaseIterable, Equatable {
        case bug
        case idea
        case other
    }

    @ObservableState
    struct State: Equatable {
        var me: UserProfile
        var category: Category = .bug
        var content: String = ""
        var contactEmail: String = ""
        var didPrefillEmail = false
        var isSubmitting = false
        @Presents var alert: AlertState<Action.Alert>?

        /// 訊息上限，跟 migration 的 char_length check 對齊。
        static let maxContentLength = 2000

        var trimmedContent: String {
            content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var canSubmit: Bool {
            !trimmedContent.isEmpty
                && trimmedContent.count <= Self.maxContentLength
                && !isSubmitting
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case onAppear
        case emailPrefilled(String?)
        case submitTapped
        case submitSucceeded
        case submitFailed(String)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)

        enum Alert: Equatable {}

        @CasePathable
        enum Delegate: Equatable {
            case submitted
        }
    }

    @Dependency(\.feedbackClient) var feedbackClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .onAppear:
                sentryClient.addBreadcrumb(
                    category: "feedback",
                    message: "feedback.opened"
                )
                // 預填登入帳號 email，使用者可改可清空。只填一次，避免覆蓋使用者輸入。
                guard !state.didPrefillEmail else { return .none }
                return .run { send in
                    let email = await feedbackClient.currentEmail()
                    await send(.emailPrefilled(email))
                }

            case let .emailPrefilled(email):
                state.didPrefillEmail = true
                if state.contactEmail.isEmpty, let email {
                    state.contactEmail = email
                }
                return .none

            case .binding:
                return .none

            case .submitTapped:
                guard state.canSubmit else { return .none }
                state.isSubmitting = true
                sentryClient.addBreadcrumb(
                    category: "feedback",
                    message: "feedback.submit_tapped",
                    data: ["category": state.category.rawValue]
                )
                let submission = FeedbackSubmission(
                    userID: state.me.id,
                    category: state.category.rawValue,
                    content: state.trimmedContent,
                    contactEmail: state.contactEmail,
                    isPremium: state.me.isPremium
                )
                return .run { send in
                    do {
                        try await feedbackClient.submit(submission)
                        await send(.submitSucceeded)
                    } catch {
                        await send(.submitFailed(error.localizedDescription))
                    }
                }

            case .submitSucceeded:
                state.isSubmitting = false
                sentryClient.addBreadcrumb(
                    category: "feedback",
                    message: "feedback.submit_succeeded"
                )
                return .send(.delegate(.submitted))

            case let .submitFailed(message):
                state.isSubmitting = false
                sentryClient.addBreadcrumb(
                    category: "feedback",
                    message: "feedback.submit_failed",
                    level: .warning
                )
                state.alert = AlertState {
                    TextState(LS("feedback.error_title"))
                } actions: {
                    ButtonState(role: .cancel) { TextState(LS("common.ok")) }
                } message: {
                    TextState(message)
                }
                return .none

            case .alert:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}
