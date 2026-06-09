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
        var isAtSendLimit: Bool = false
        var isLoading = false
        var errorMessage: String?
        @Presents var compose: ComposeFeature.State?
        @Presents var paywall: PaywallFeature.State?

        var currentUserID: UUID = UUID()
        var senderName: String = ""
        var showLimitInfo: Bool = false
        var isPremium: Bool = false

        var scheduledCountToFriend: Int {
            messages.filter {
                $0.senderID == currentUserID &&
                $0.status == .scheduled &&
                $0.unlockAt > now
            }.count
        }

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
        case upgradeTapped
        case deleteTapped(UUID)
        case deleteResponse(id: UUID, error: String?)
        case compose(PresentationAction<ComposeFeature.Action>)
        case paywall(PresentationAction<PaywallFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case messageSent(DelayedMessage)
            case purchaseSucceeded(UserProfile)
        }
    }

    private enum CancelID { case timer, load }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.messagesCacheClient) var messagesCacheClient
    @Dependency(\.revealGateClient) var revealGateClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.currentUserClient) var currentUserClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                if state.messages.isEmpty {
                    let cached = messagesCacheClient.load(state.currentUserID, state.friend.id)
                    if !cached.isEmpty {
                        state.messages = IdentifiedArray(
                            uniqueElements: cached.sorted { $0.unlockAt < $1.unlockAt }
                        )
                        state.isLoading = false
                    } else {
                        state.isLoading = true
                    }
                }
                refreshIsAtSendLimit(&state)
                return .merge(startTimer(), loadThread(userID: state.currentUserID, friendID: state.friend.id))

            case .timerTick(let now):
                state.now = now
                for id in state.messages.ids {
                    if state.messages[id: id]?.status == .scheduled,
                       let unlockAt = state.messages[id: id]?.unlockAt,
                       now >= unlockAt {
                        state.messages[id: id]?.status = .readyToReveal
                    }
                }
                refreshIsAtSendLimit(&state)
                return .none

            case .composeTapped:
                refreshIsAtSendLimit(&state)
                if state.isAtSendLimit {
                    state.showLimitInfo = true
                } else {
                    state.compose = ComposeFeature.State(
                        friend: state.friend,
                        senderID: state.currentUserID,
                        senderName: state.senderName,
                        isPremium: currentUserClient.isPremium(),
                        maxDelaySeconds: currentUserClient.maxDelaySeconds()
                    )
                }
                return .none

            case .revealTapped(let id):
                guard let message = state.messages[id: id],
                      message.status == .readyToReveal else { return .none }
                sentryClient.addBreadcrumb(
                    category: "reveal",
                    message: "reveal.tapped",
                    data: ["messageID": id.uuidString]
                )
                let now = date()
                return .run { send in
                    let result = await revealGateClient.canReveal(message, now)
                    await send(.revealResponse(id: id, result: result))
                }

            case .revealResponse(let id, let result):
                switch result {
                case true:
                    sentryClient.addBreadcrumb(
                        category: "reveal",
                        message: "reveal.succeeded",
                        data: ["messageID": id.uuidString]
                    )
                    let now = date()
                    state.messages[id: id]?.status = .revealed
                    state.messages[id: id]?.revealedAt = now
                    return .run { send in
                        do {
                            try await messageClient.reveal(id, now)
                        } catch {
                            await send(.revealCommitFailed(id))
                        }
                    }
                case false:
                    sentryClient.addBreadcrumb(
                        category: "reveal",
                        message: "reveal.gate_blocked",
                        level: .warning,
                        data: ["reason": "time_invalid"]
                    )
                    state.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
                case nil:
                    sentryClient.addBreadcrumb(
                        category: "reveal",
                        message: "reveal.gate_unavailable",
                        level: .warning,
                        data: ["reason": "network"]
                    )
                    state.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
                }
                return .none

            case .revealCommitFailed(let id):
                sentryClient.addBreadcrumb(
                    category: "reveal",
                    message: "reveal.commit_failed",
                    level: .warning,
                    data: ["messageID": id.uuidString]
                )
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
                refreshIsAtSendLimit(&state)
                let userID = state.currentUserID
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
                let userID = state.currentUserID
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
                    refreshIsAtSendLimit(&state)
                }
                return .none

            case .limitInfoDismissed:
                state.showLimitInfo = false
                return .none

            case .upgradeTapped:
                state.showLimitInfo = false
                state.paywall = PaywallFeature.State()
                return .none

            case .paywall(.presented(.delegate(.purchaseSucceeded(let profile)))):
                state.paywall = nil
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .paywall:
                return .none

            case .compose(.presented(.delegate(.purchaseSucceeded(let profile)))):
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .compose(.presented(.sendSucceeded(let message))):
                state.messages.append(message)
                refreshIsAtSendLimit(&state)
                state.compose = nil
                let updatedMessages = Array(state.messages)
                let userID = state.currentUserID
                let friendID = state.friend.id
                return .merge(
                    .run { _ in messagesCacheClient.save(updatedMessages, userID, friendID) },
                    .send(.delegate(.messageSent(message)))
                )

            case .compose(.presented(.sendFailed(let error))):
                state.compose = nil
                if error.contains("friend_message_limit_exceeded") {
                    state.errorMessage = "已達上限，等訊息開啟後再傳"
                } else if error.contains("delay_seconds_exceeds_free_limit") {
                    state.errorMessage = "免費版倒數最長 24 小時，升級 Premium 可解鎖更長倒數"
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
        .ifLet(\.$paywall, action: \.paywall) {
            PaywallFeature()
        }
    }

    private func refreshIsAtSendLimit(_ state: inout State) {
        state.isPremium = currentUserClient.isPremium()
        state.isAtSendLimit = state.scheduledCountToFriend >= currentUserClient.messageLimit()
    }

    private func startTimer() -> Effect<Action> {
        .run { [date] send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.timerTick(date()))
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func loadThread(userID: UUID, friendID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let messages = try await messageClient.fetchThread(userID, friendID)
                await send(.messagesLoaded(messages))
            } catch {
                await send(.loadFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
