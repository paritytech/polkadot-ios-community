import BigInt
import Foundation
import Operation_iOS
import SubstrateSdk

/// A single entry in a claim plan, mapping a memo entry index to its pre-allocated destination coin.
public struct ClaimPlanEntry: Equatable, Sendable {
    /// Index into the original ``TransferMemo/entries`` array.
    public let entryIndex: Int
    /// The destination coin allocated for this entry during claim planning.
    public let destinationCoin: Coin

    public init(
        entryIndex: Int,
        destinationCoin: Coin
    ) {
        self.entryIndex = entryIndex
        self.destinationCoin = destinationCoin
    }
}

/// Persisted record of a coinage claim or send operation.
///
/// Plans serve dual purpose: recovery artifacts (so interrupted claims can resume with
/// pre-allocated coins) and status markers (so the UI can display claim/send progress
/// even after app restart, when source coins may already be destroyed).
public struct ClaimPlan: Equatable, Sendable {
    /// Coarse persistence status for CoreData storage.
    public enum Status: Int, Sendable {
        case processing = 0
        case finished = 1
        case error = 2
        /// Coins confirmed on-chain. Outgoing: awaiting recipient claim. Incoming: ready to submit claim extrinsic.
        case detected = 3
    }

    /// Dedup key — concatenated private keys from the memo.
    public let memoKey: Data
    /// Link to the chat message that triggered this claim.
    public let messageId: String
    /// Pre-allocated destination coins for each memo entry.
    public let entries: [ClaimPlanEntry]
    /// Persisted status of this claim/send operation.
    public let status: Status
    /// The memo's expected total value in planks, stored at plan creation.
    public let totalValue: Balance
    /// Actual claimed amount in planks, computed on claim success and persisted.
    public let claimedAmount: Balance?

    public init(
        memoKey: Data,
        messageId: String,
        entries: [ClaimPlanEntry],
        status: Status = .processing,
        totalValue: Balance,
        claimedAmount: Balance? = nil
    ) {
        self.memoKey = memoKey
        self.messageId = messageId
        self.entries = entries
        self.status = status
        self.totalValue = totalValue
        self.claimedAmount = claimedAmount
    }
}

extension ClaimPlan: Operation_iOS.Identifiable {
    public var identifier: String {
        memoKey.toHex()
    }
}
