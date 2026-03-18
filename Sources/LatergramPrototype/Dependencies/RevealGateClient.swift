import ComposableArchitecture
import LatergramCore
import Foundation

/// Asks the server whether a message is unlockable at a given time.
/// Live implementation will call a Supabase RPC; for now stubs use local time.
@DependencyClient
struct RevealGateClient: Sendable {
    var canReveal: @Sendable (_ message: DelayedMessage, _ now: Date) async -> Bool = { _, _ in false }
}

extension RevealGateClient: DependencyKey {
    static let liveValue = RevealGateClient(
        canReveal: { message, _ in          // ignore local now; server decides
            struct Params: Encodable { let message_id: UUID }
            do {
                let allowed: Bool = try await supabase
                    .rpc("can_reveal_message", params: Params(message_id: message.id))
                    .execute()
                    .value
                return allowed
            } catch {
                return false               // network failure → deny (fail-safe)
            }
        }
    )
    static let testValue = RevealGateClient(
        canReveal: { message, now in now >= message.unlockAt }  // local time — controllable in tests
    )
}

extension DependencyValues {
    var revealGateClient: RevealGateClient {
        get { self[RevealGateClient.self] }
        set { self[RevealGateClient.self] = newValue }
    }
}
