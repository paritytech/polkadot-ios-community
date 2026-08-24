import Foundation

/// The finalized and best heads a single recovery pass evaluates against.
///
/// Both heads come from one connection and are read once, so every rule in the pass
/// sees the same chain. `connectionToken` identifies that connection: if it is replaced
/// mid-pass the pass aborts rather than mixing views from two peers.
public struct ChainView: Sendable, Equatable {
    public let finalized: BlockRef
    public let best: BlockRef
    public let connectionToken: UUID

    public init(finalized: BlockRef, best: BlockRef, connectionToken: UUID) {
        self.finalized = finalized
        self.best = best
        self.connectionToken = connectionToken
    }
}
