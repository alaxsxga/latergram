import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct ComposeFeature {
    @ObservableState
    struct State: Equatable {
        enum TimingMode: Equatable { case countdown, unlockDate }

        let friend: Friend
        let senderID: UUID
        let senderName: String
        var body = ""
        var unlockAt = Date().addingTimeInterval(60)
        var delaySeconds: Int = 60
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

                // Compute final unlockAt and delaySeconds at submit time.
                // Countdown mode: delaySeconds is the intent; unlockAt is derived now.
                // UnlockDate mode: the chosen date is the intent; delaySeconds is derived now.
                let finalUnlockAt: Date
                let finalDelaySeconds: Int
                switch state.timingMode {
                case .countdown:
                    finalDelaySeconds = state.delaySeconds
                    finalUnlockAt = now.addingTimeInterval(TimeInterval(finalDelaySeconds))
                case .unlockDate:
                    finalUnlockAt = state.unlockAt
                    finalDelaySeconds = max(60, Int(finalUnlockAt.timeIntervalSince(now)))
                }

                if let error = rules.validate(body: state.body, unlockAt: finalUnlockAt, now: now) {
                    state.errorMessage = errorText(for: error)
                    return .none
                }
                state.isSending = true
                state.errorMessage = nil
                let message = DelayedMessage(
                    senderID: state.senderID,
                    receiverID: state.friend.id,
                    senderName: state.senderName,
                    receiverName: state.friend.displayName,
                    body: state.body,
                    style: state.style,
                    sentAt: now,
                    unlockAt: finalUnlockAt,
                    delaySeconds: finalDelaySeconds,
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
        }
    }
}
