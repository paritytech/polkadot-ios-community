import Foundation

/// Expiry for statements that must disappear soon: `(now + lifetime) << 32`, with the low 32 bits left for the
/// sequence that `PeerSessionPriorityProvider` adds on each increment.
public final class ShortLivedStatementPriorityFactory {
    private let lifetimeInSeconds: TimeInterval
    private let timeProvider: SynchronousTimeProviding

    public init(lifetimeInSeconds: TimeInterval, timeProvider: SynchronousTimeProviding = SystemTimeProvider()) {
        self.lifetimeInSeconds = lifetimeInSeconds
        self.timeProvider = timeProvider
    }
}

extension ShortLivedStatementPriorityFactory: StatementPriorityMaking {
    public func makeTimestampPriority() -> UInt64 {
        let now = timeProvider.now.timeIntervalSince1970
        return UInt64(now + lifetimeInSeconds) << 32
    }
}
