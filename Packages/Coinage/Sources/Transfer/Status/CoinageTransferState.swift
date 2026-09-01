import Foundation
import SubstrateSdk

/// The Appendix-A derived payment status of a coin we handed off: whether the peer has taken it.
///
/// Not part of the tracking model — each value is computed on read from the coin's minter status and
/// its presence at the finalized head, never stored.
public enum CoinageTransferStatus: Equatable, Sendable {
    /// Present on chain: the peer has not taken it yet.
    case awaitingClaim

    /// Absent, and its minter has not resolved: it may simply not exist yet.
    case detecting

    /// Absent because it was never minted. The key controls nothing, and nothing can change that.
    case failed

    /// Absent after having existed, so the peer took it.
    ///
    /// `finalized` separates a guess from a proof: true only when the mint finalized *and* the coin
    /// is absent from the finalized chain. Until then it is inferred from the best head, where a fork
    /// can put the coin back.
    case claimed(finalized: Bool)
}

public extension CoinageTransferStatus {
    /// Whether nothing can change this any more — and so whether a payment may be closed on it.
    var isTerminal: Bool {
        switch self {
        case .failed: true
        case let .claimed(finalized): finalized
        case .awaitingClaim,
             .detecting: false
        }
    }
}

/// A handed-off coin paired with its derived payment status.
public struct CoinageTransferState: Equatable, Sendable {
    public let coin: Coin
    public let status: CoinageTransferStatus

    public init(coin: Coin, status: CoinageTransferStatus) {
        self.coin = coin
        self.status = status
    }
}
