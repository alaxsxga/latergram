import Foundation

public protocol RevealGateService: Sendable {
    func canReveal(message: DelayedMessage, at now: Date) async -> Bool
}

public struct DemoRevealGateService: RevealGateService {
    public init() {}

    public func canReveal(message: DelayedMessage, at now: Date) async -> Bool {
        now >= message.unlockAt
    }
}
