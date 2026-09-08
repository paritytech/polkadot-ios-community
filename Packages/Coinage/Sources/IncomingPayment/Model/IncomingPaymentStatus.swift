import Foundation
import SubstrateSdk

/// Observable status of an incoming payment. Derived from the CoinageTx durability layer plus
/// on-chain detection — never persisted on the record (the `groupId` is the source of truth).
///
/// Terminal statuses never advance: `claimed(finalized: true)`, `claimedPartially`, `notClaimed`.
public enum IncomingPaymentStatus: Equatable, Sendable {
    /// Waiting for the needed amount to appear on the source.
    case detecting
    /// Claim in progress.
    case claiming
    /// At least `amount` was claimed at best/finalized head, depending on `finalized`.
    /// Terminal when `finalized == true`.
    case claimed(finalized: Bool)
    /// Terminal. Only `actualClaimed < amount` could be claimed.
    case claimedPartially(actualClaimed: Balance)
    /// Terminal. Nothing could be claimed.
    case notClaimed
}

public extension IncomingPaymentStatus {
    var isTerminal: Bool {
        switch self {
        case .detecting, .claiming:
            false
        case let .claimed(finalized):
            finalized
        case .claimedPartially, .notClaimed:
            true
        }
    }
}
