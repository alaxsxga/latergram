import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct ChatDetailFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID { friend.id }
        let friend: Friend
        var messages: IdentifiedArrayOf<DelayedMessage> = []
        var now: Date = Date()
        var lastSentAt: Date?
        var isLoading = false
        var errorMessage: String?
        @Presents var compose: ComposeFeature.State?
    }

    enum Action {
        case onAppear
        case timerTick(Date)
        case composeTapped
        case revealTapped(UUID)
        case revealResponse(id: UUID, result: Bool?)
        case messagesLoaded([DelayedMessage])
        case loadFailed(String)
        case errorDismissed
        case compose(PresentationAction<ComposeFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case messageSent(DelayedMessage)
        }
    }

    private enum CancelID { case timer, load }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.revealGateClient) var revealGateClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.currentUser) var currentUser

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                state.isLoading = true
                return .merge(startTimer(), loadThread(friendID: state.friend.id))

            case .timerTick(let now):
                state.now = now
                return .none

            case .composeTapped:
                state.compose = ComposeFeature.State(
                    friend: state.friend,
                    lastSentAt: state.lastSentAt
                )
                return .none

            case .revealTapped(let id):
                guard let message = state.messages[id: id],
                      message.status == .readyToReveal else { return .none }
                let now = date()
                return .run { send in
                    let result = await revealGateClient.canReveal(message, now)
                    await send(.revealResponse(id: id, result: result))
                }

            case .revealResponse(let id, let result):
                switch result {
                case true:
                    state.messages[id: id]?.status = .revealed
                    state.messages[id: id]?.revealedAt = date()
                case false:
                    state.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
                case nil:
                    state.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
                }
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                state.messages = IdentifiedArray(
                    uniqueElements: messages.sorted { $0.unlockAt < $1.unlockAt }
                )
                return .none

            case .loadFailed(let error):
                state.isLoading = false
                state.errorMessage = error
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .compose(.presented(.sendSucceeded(let message))):
                state.messages.append(message)
                state.lastSentAt = date()
                state.compose = nil
                return .send(.delegate(.messageSent(message)))

            case .delegate:
                return .none

            case .compose(.presented(.cancelTapped)):
                state.compose = nil
                return .none

            case .compose:
                return .none
            }
        }
        .ifLet(\.$compose, action: \.compose) {
            ComposeFeature()
        }
    }

    private func startTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.timerTick(Date()))
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func loadThread(friendID: UUID) -> Effect<Action> {
        .run { [currentUser] send in
            do {
                let messages = try await messageClient.fetchThread(currentUser.id, friendID)
                await send(.messagesLoaded(messages))
            } catch {
                await send(.loadFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
