import Foundation

/// Expiry for statements that must disappear soon: `(now + lifetime) << 32`, with the low 32 bits left for the
/// sequence that `PeerSessionPriorityProvider` adds on each increment.
public final class ShortLivedStatementPriorityFactory {
    private let lifetimeInSeconds: TimeInterval

    public init(lifetimeInSeconds: TimeInterval) {
        self.lifetimeInSeconds = lifetimeInSeconds
    }
}

extension ShortLivedStatementPriorityFactory: StatementPriorityMaking {
    public func makeTimestampPriority() -> UInt64 {
        let now = Date().timeIntervalSince1970
        return UInt64(now + lifetimeInSeconds) << 32
    }
}
