import ComposableArchitecture
import LatergramCore
import Foundation

@Reducer
struct CountdownInboxFeature {
    @ObservableState
    struct State: Equatable {
        var messages: IdentifiedArrayOf<DelayedMessage> = []
        var receivedPendingSortOrder: [UUID] = []  // 接收：時間到優先，再依 unlockAt 升冪
        var sentPendingSortOrder: [UUID] = []      // 發送：依 sentAt 降冪
        var revealedSortOrder: [UUID] = []         // 已開啟（接收與發送共用）：依 sentAt 降冪
        var lastFetchedAt: Date? = nil
        var now: Date = Date()
        var isLoading = false
        var errorMessage: String?
        var infoBanner: String?
        var lastNotificationRebuildAt: Date?
        var currentUserID: UUID = UUID()
    }

    enum Action {
        case onAppear
        case messageSent(DelayedMessage)
        case foregroundRefresh
        case refreshRequested
        case timerTick(Date)
        case revealTapped(UUID)
        case revealResponse(id: UUID, result: Bool?)
        case messagesLoaded([DelayedMessage])
        case loadFailed(String)
        case errorDismissed
        case deleteTapped(UUID)
        case deleteResponse(id: UUID, error: String?)
    }

    enum CancelID { case timer, load }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.revealGateClient) var revealGateClient
    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.currentUser) var currentUser

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                state.currentUserID = currentUser.id
                let now = date()
                applySort(to: &state, now: now)
                let shouldFetch = state.lastFetchedAt.map { now.timeIntervalSince($0) > 30 } ?? true
                if state.messages.isEmpty { state.isLoading = true }
                var effects: [Effect<Action>] = [
                    startTimer(),
                    .run { _ in _ = await notificationClient.requestPermission() }
                ]
                if shouldFetch {
                    effects.append(loadMessages(userID: currentUser.id))
                }
                return .merge(effects)

            case .messageSent(let message):
                state.messages.updateOrAppend(message)
                return .none

            case .refreshRequested:
                return loadMessages(userID: currentUser.id)

            case .foregroundRefresh:
                let now = date()
                let policy = NotificationRebuildPolicy()
                guard policy.shouldRebuild(lastRebuildAt: state.lastNotificationRebuildAt, now: now) else {
                    return .none
                }
                state.lastNotificationRebuildAt = now
                for id in state.messages.ids {
                    if state.messages[id: id]?.status == .scheduled,
                       let unlockAt = state.messages[id: id]?.unlockAt,
                       now >= unlockAt {
                        state.messages[id: id]?.status = .readyToReveal
                    }
                }
                let toSchedule = policy.selectMessagesForScheduling(Array(state.messages), now: now)
                state.infoBanner = "已重排本地通知 \(toSchedule.count) 則"
                return .merge(
                    loadMessages(userID: currentUser.id),
                    .run { [toSchedule] _ in
                        await notificationClient.scheduleMessages(toSchedule)
                    }
                )

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
                    return .run { _ in
                        try? await messageClient.reveal(id, now)
                    }
                case false:
                    state.errorMessage = "訊息尚未到達解鎖時間，請確認手機時間是否正確"
                case nil:
                    state.errorMessage = "無法連線至伺服器，請確認網路連線後再試"
                }
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                let now = date()
                // Hide revealed messages older than 2 days; always show unrevealed (even if overdue)
                let twoDays: TimeInterval = 2 * 24 * 60 * 60
                let filtered = messages.filter { msg in
                    guard msg.status == .revealed else { return true }
                    return now.timeIntervalSince(msg.revealedAt ?? msg.unlockAt) < twoDays
                }
                // Apply client-side scheduled → readyToReveal transition immediately
                // so the first render matches what the timer would produce, avoiding a flash
                let transitioned = filtered.map { msg -> DelayedMessage in
                    guard msg.status == .scheduled, now >= msg.unlockAt else { return msg }
                    var m = msg
                    m.status = .readyToReveal
                    return m
                }
                state.messages = IdentifiedArray(uniqueElements: transitioned)
                state.lastFetchedAt = now
                applySort(to: &state, now: now)
                return .none

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
            }
        }
    }

    private func applySort(to state: inout State, now: Date) {
        let pending = state.messages.filter { $0.status != .revealed }
        let revealed = state.messages.filter { $0.status == .revealed }
        // 接收：時間到的在最上面，再依 unlockAt 升冪（最短倒數在上）
        state.receivedPendingSortOrder = pending.sorted { a, b in
            let aExpired = a.unlockAt <= now
            let bExpired = b.unlockAt <= now
            if aExpired != bExpired { return aExpired }
            return a.unlockAt < b.unlockAt
        }.map(\.id)
        // 發送：最新發送在最上面
        state.sentPendingSortOrder = pending
            .sorted { $0.sentAt > $1.sentAt }
            .map(\.id)
        // 已開啟：最新發送在最上面（接收與發送共用）
        state.revealedSortOrder = revealed
            .sorted { $0.sentAt > $1.sentAt }
            .map(\.id)
    }

    private func startTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.timerTick(Date()))
            }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    private func loadMessages(userID: UUID) -> Effect<Action> {
        .run { send in
            do {
                let messages = try await messageClient.fetchCountdownFeed(userID)
                await send(.messagesLoaded(messages))
            } catch {
                await send(.loadFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
