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

        var lastNotificationRebuildAt: Date?
        var currentUserID: UUID = UUID()
        var currentUserName: String = ""
        var friends: [Friend] = []
        var isLoadingFriends: Bool = false
        var showRecipientPicker: Bool = false
        var showLimitInfo: Bool = false
        var limitInfoUnlockAt: Date? = nil
        var isPremium: Bool = false
        @Presents var compose: ComposeFeature.State?
        @Presents var paywall: PaywallFeature.State?
    }

    enum Action {
        case onAppear
        case messageSent(DelayedMessage)
        case foregroundRefresh
        case refreshRequested
        case timerTick(Date)
        case revealTapped(UUID)
        case revealResponse(id: UUID, result: Bool?)
        case revealCommitFailed(UUID)
        case messagesLoaded([DelayedMessage])
        case loadFailed(String)
        case errorDismissed
        case deleteTapped(UUID)
        case deleteResponse(id: UUID, error: String?)
        case plusTapped
        case friendsLoaded([Friend])
        case recipientSelected(Friend)
        case recipientPickerDismissed
        case limitInfoDismissed
        case upgradeTapped
        case compose(PresentationAction<ComposeFeature.Action>)
        case paywall(PresentationAction<PaywallFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case purchaseSucceeded(UserProfile)
        }
    }

    enum CancelID { case timer, load, messageStream }

    @Dependency(\.messageClient) var messageClient
    @Dependency(\.revealGateClient) var revealGateClient
    @Dependency(\.notificationClient) var notificationClient
    @Dependency(\.friendClient) var friendClient
    @Dependency(\.friendsCacheClient) var friendsCacheClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date
    @Dependency(\.currentUserClient) var currentUserClient
    @Dependency(\.sentryClient) var sentryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {

            case .onAppear:
                let now = date()
                applySort(to: &state, now: now)
                let shouldFetch = state.lastFetchedAt.map { now.timeIntervalSince($0) > 30 } ?? true
                if state.messages.isEmpty { state.isLoading = true }
                var effects: [Effect<Action>] = [
                    startTimer(),
                    startMessageStream(userID: state.currentUserID),
                    .run { _ in _ = await notificationClient.requestPermission() }
                ]
                if shouldFetch {
                    effects.append(loadMessages(userID: state.currentUserID))
                }
                return .merge(effects)

            case .messageSent(let message):
                state.messages.updateOrAppend(message)
                applySort(to: &state, now: date())
                return .none

            case .refreshRequested:
                return loadMessages(userID: state.currentUserID)

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
                let incoming = state.messages.filter { $0.receiverID == state.currentUserID }
                let toSchedule = policy.selectMessagesForScheduling(Array(incoming), now: now)
                return .merge(
                    loadMessages(userID: state.currentUserID),
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
                    applySort(to: &state, now: now)
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
                applySort(to: &state, now: date())
                state.errorMessage = "開啟失敗，請確認網路後再試"
                return .none

            case .messagesLoaded(let messages):
                state.isLoading = false
                let now = date()
                // Hide revealed messages older than 2 days; always show unrevealed (even if overdue)
                let twoDays: TimeInterval = 2 * 24 * 60 * 60
                let filtered = messages.filter { msg in
                    guard msg.status == .revealed else { return true }
                    guard let revealedAt = msg.revealedAt else { return true }
                    return now.timeIntervalSince(revealedAt) < twoDays
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
                state.lastNotificationRebuildAt = now
                applySort(to: &state, now: now)
                let policy = NotificationRebuildPolicy()
                let currentUserID = state.currentUserID
                let incoming = transitioned.filter { $0.receiverID == currentUserID }
                let toSchedule = policy.selectMessagesForScheduling(incoming, now: now)
                return .run { [toSchedule] _ in
                    await notificationClient.scheduleMessages(toSchedule)
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
                }
                return .none

            case .plusTapped:
                state.showRecipientPicker = true
                let cached = friendsCacheClient.load(state.currentUserID).filter { $0.status == .accepted }
                    .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                state.friends = cached
                if cached.isEmpty {
                    state.isLoadingFriends = true
                    return .run { [id = state.currentUserID] send in
                        let friends = (try? await friendClient.fetchFriends(id)) ?? []
                        await send(.friendsLoaded(friends))
                    }
                }
                return .none

            case .friendsLoaded(let friends):
                state.isLoadingFriends = false
                let accepted = friends.filter { $0.status == .accepted }
                    .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                state.friends = accepted
                friendsCacheClient.save(accepted, state.currentUserID)
                return .none

            case .recipientSelected(let friend):
                state.showRecipientPicker = false
                let scheduled = state.messages.filter {
                    $0.senderID == state.currentUserID &&
                    $0.receiverID == friend.id &&
                    $0.status == .scheduled &&
                    $0.unlockAt > state.now
                }
                if scheduled.count >= currentUserClient.messageLimit() {
                    state.limitInfoUnlockAt = scheduled.map(\.unlockAt).min()
                    state.isPremium = currentUserClient.isPremium()
                    state.showLimitInfo = true
                    return .none
                }
                state.compose = ComposeFeature.State(
                    friend: friend,
                    senderID: state.currentUserID,
                    senderName: state.currentUserName,
                    isPremium: currentUserClient.isPremium(),
                    maxDelaySeconds: currentUserClient.maxDelaySeconds()
                )
                return .none

            case .recipientPickerDismissed:
                state.showRecipientPicker = false
                return .none

            case .limitInfoDismissed:
                state.showLimitInfo = false
                state.limitInfoUnlockAt = nil
                return .none

            case .upgradeTapped:
                state.showLimitInfo = false
                state.limitInfoUnlockAt = nil
                state.paywall = PaywallFeature.State()
                return .none

            case .paywall(.presented(.delegate(.purchaseSucceeded(let profile)))):
                state.paywall = nil
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .paywall:
                return .none

            case .delegate:
                return .none

            case .compose(.presented(.delegate(.purchaseSucceeded(let profile)))):
                return .send(.delegate(.purchaseSucceeded(profile)))

            case .compose(.presented(.sendSucceeded(let message))):
                state.compose = nil
                return .send(.messageSent(message))

            case .compose(.presented(.sendFailed)):
                state.compose = nil
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

    private func startMessageStream(userID: UUID) -> Effect<Action> {
        .run { send in
            for await _ in messageClient.messageStream(userID) {
                await send(.refreshRequested)
            }
        }
        .cancellable(id: CancelID.messageStream, cancelInFlight: true)
    }

    private func startTimer() -> Effect<Action> {
        .run { [date] send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.timerTick(date()))
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
