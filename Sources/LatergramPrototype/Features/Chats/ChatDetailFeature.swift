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
        var userMessageLimit: Int = 1
        var isLoading = false
        var errorMessage: String?
        @Presents var compose: ComposeFeature.State?

        var currentUserID: UUID = UUID()
        var showLimitInfo: Bool = false

        var scheduledCountToFriend: Int {
            messages.filter {
                $0.senderID == currentUserID &&
                $0.status == .scheduled &&
                $0.unlockAt > now
            }.count
        }

        var isAtSendLimit: Bool { scheduledCountToFriend >= userMessageLimit }

        var earliestBlockedUnlockAt: Date? {
            messages
                .filter { $0.senderID == currentUserID && $0.status == .scheduled && $0.unlockAt > now }
                .map(\.unlockAt).min()
        }
    }

    enum Action {
        case onAppear
        case timerTick(Date)
        case composeTapped
        case revealTapped(UUID)
        case revealResponse(id: UUID, result: Bool?)
        case revealCommitFailed(UUID)
        case messagesLoaded([DelayedMessage])
        case loadFailed(String)
        case errorDismissed
        case limitInfoDismissed
        case messageLimitUpdated(Int)
        case deleteTapped(UUID)
        case deleteResponse(id: UUID, error: String?)
        case compose(PresentationAction<ComposeFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case messageSent(DelayedMessage)
        }
    }

    private enum CancelID { case timer, load }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.messagesCacheClient) var messagesCacheClient
    @Dependency(\.revealGateClient) var revealGateClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.currentUser) var currentUser

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                state.currentUserID = currentUser.id
                state.userMessageLimit = currentUser.messageLimit
                let cached = messagesCacheClient.load(currentUser.id, state.friend.id)
                if !cached.isEmpty {
                    state.messages = IdentifiedArray(
                        uniqueElements: cached.sorted { $0.unlockAt < $1.unlockAt }
                    )
                    state.isLoading = false
                } else {
                    state.isLoading = true
                }
                return .merge(startTimer(), loadThread(friendID: state.friend.id))

            case .timerTick(let now):
                state.now = now
                for id in state.messages.ids {
                    if state.messages[id: id]?.status == .scheduled,
                       let unlockAt = state.messages[id: id]?.unlockAt,
                       now >= unlockAt {
                        state.messages[id: id]?.status = .readyToReveal
                    }
                }
                return .none

            case .composeTapped:
                if state.isAtSendLimit {
                    state.showLimitInfo = true
                } else {
                    state.compose = ComposeFeature.State(friend: state.friend)
                }
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
                    let now = date()
                    return .run { send in
                        do {
                            try await messageClient.reveal(id, now)
                        } catch {
                            await send(.revealCommitFailed(id))
                        }
                    }
                case false:
                    state.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
                case nil:
                    state.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
                }
                return .none

            case .revealCommitFailed(let id):
                state.messages[id: id]?.status = .readyToReveal
                state.messages[id: id]?.revealedAt = nil
                state.errorMessage = "開啟失敗，請確認網路後再試"
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                let now = date()
                let sorted = messages.sorted { $0.unlockAt < $1.unlockAt }
                // Apply client-side scheduled → readyToReveal transition immediately
                // so the first render matches what the timer would produce, avoiding a flash
                let transitioned = sorted.map { msg -> DelayedMessage in
                    guard msg.status == .scheduled, now >= msg.unlockAt else { return msg }
                    var m = msg
                    m.status = .readyToReveal
                    return m
                }
                state.messages = IdentifiedArray(uniqueElements: transitioned)
                let userID = currentUser.id
                let friendID = state.friend.id
                return .run { [transitioned] _ in
                    messagesCacheClient.save(transitioned, userID, friendID)
                }

            case .loadFailed(let error):
                state.isLoading = false
                state.errorMessage = error
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .deleteTapped(let id):
                let userID = currentUser.id
                return .run { send in
                    do {
                        try await messageClient.delete(id, userID)
                        await send(.deleteResponse(id: id, error: nil))
                    } catch {
                        await send(.deleteResponse(id: id, error: error.localizedDescription))
                    }
                }

            case .deleteResponse(let id, let error):
                if let error {
                    state.errorMessage = error
                } else {
                    state.messages.remove(id: id)
                }
                return .none

            case .limitInfoDismissed:
                state.showLimitInfo = false
                return .none

            case .messageLimitUpdated(let limit):
                state.userMessageLimit = limit
                return .none

            case .compose(.presented(.sendSucceeded(let message))):
                state.messages.append(message)
                state.compose = nil
                return .send(.delegate(.messageSent(message)))

            case .compose(.presented(.sendFailed(let error))):
                state.compose = nil
                if error.contains("friend_message_limit_exceeded") {
                    state.errorMessage = "已達上限，等訊息開啟後再傳"
                } else {
                    state.errorMessage = error
                }
                return .none

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
