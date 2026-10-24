import Foundation

/// Expiry for statements that must disappear soon: `(now + lifetime) << 32`, with the low 32 bits left for the
/// sequence that `PeerSessionPriorityProvider` adds on each increment.
public final class ShortLivedStatementPriorityFactory {
    private let lifetimeInSeconds: UInt64

    public init(lifetimeInSeconds: UInt64) {
        self.lifetimeInSeconds = lifetimeInSeconds
    }
}

extension ShortLivedStatementPriorityFactory: StatementPriorityMaking {
    public func makeTimestampPriority() -> UInt64 {
        let now = UInt64(Date().timeIntervalSince1970)
        return (now + lifetimeInSeconds) << 32
    }
}
