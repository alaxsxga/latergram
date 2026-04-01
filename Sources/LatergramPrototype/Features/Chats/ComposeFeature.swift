import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct ComposeFeature {
    @ObservableState
    struct State: Equatable {
        enum TimingMode: Equatable { case countdown, unlockDate }

        let friend: Friend
        var body = ""
        var unlockAt = Date().addingTimeInterval(60)
        var style: MessageStyle = .classic
        var timingMode: TimingMode = .countdown
        var errorMessage: String?
        var isSending = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case submitTapped
        case cancelTapped
        case sendSucceeded(DelayedMessage)
        case sendFailed(String)
    }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.currentUser) var currentUser
    @Dependency(\.date) var date

    private let rules = MessageComposerRules()

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {

            case .binding:
                return .none

            case .submitTapped:
                let now = date()
                if let error = rules.validate(
                    body: state.body,
                    unlockAt: state.unlockAt,
                    now: now
                ) {
                    state.errorMessage = errorText(for: error)
                    return .none
                }
                state.isSending = true
                state.errorMessage = nil
                let message = DelayedMessage(
                    senderID: currentUser.id,
                    receiverID: state.friend.id,
                    senderName: currentUser.displayName,
                    receiverName: state.friend.displayName,
                    body: state.body,
                    style: state.style,
                    sentAt: now,
                    unlockAt: state.unlockAt,
                    status: .scheduled
                )
                return .run { send in
                    do {
                        try await messageClient.send(message)
                        await send(.sendSucceeded(message))
                    } catch {
                        await send(.sendFailed(error.localizedDescription))
                    }
                }

            case .cancelTapped:
                return .none

            case .sendSucceeded:
                state.isSending = false
                return .none

            case .sendFailed(let error):
                state.isSending = false
                state.errorMessage = error
                return .none
            }
        }
    }

    private func errorText(for error: ComposeValidationError) -> String {
        switch error {
        case .emptyBody: "訊息不可為空"
        case .tooLong(let max): "訊息不可超過 \(max) 字"
        case .unlockTooSoon: "解鎖時間至少 1 分鐘後"
        case .unlockTooLate: "解鎖時間最多 7 天後"
        }
    }
}
