import BigInt
import Foundation
import SubstrateSdk

/// Rich lifecycle status for UI publishing via ``ClaimStatusPublishing``.
///
/// Unlike ``ClaimPlan/Status`` (a simple raw-Int enum for CoreData persistence),
/// this enum carries associated data and supports fine-grained UI states.
public enum ClaimStatus: Sendable, Equatable {
    /// Waiting for coins to appear on-chain (subscription active).
    case detecting
    /// Claim extrinsic submitted, waiting for confirmation.
    case claiming
    /// Outgoing transfer intermediate: coins appeared on-chain, awaiting recipient claim.
    case sent
    /// Operation completed. Carries the actual claimed amount in planks.
    case finished(claimedAmount: Balance)
    /// Operation failed (timeout, RPC error, etc.).
    case error
}

/// Broadcasts claim/send status updates to in-memory observers (e.g. chat extensions).
public protocol ClaimStatusPublishing: Sendable {
    func updateStatus(_ status: ClaimStatus, forMessageId messageId: String) async
}
