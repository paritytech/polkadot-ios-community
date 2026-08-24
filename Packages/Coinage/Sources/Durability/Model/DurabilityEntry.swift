import Foundation
import Operation_iOS

public typealias TransactionId = UUID

/// One tracked transaction: what it consumes, what it mints, and how far along it is.
///
/// The entry set is the source of truth for local asset state. Coin and voucher rows are
/// a projection of it, rebuilt by `ProjectionReconciler` at the head of every recovery
/// pass.
///
/// Deliberately operation-agnostic: every rule quantifies over `inputs` and `outputs`,
/// so all tracked calls share one resolution path and no per-operation dispatch exists.
public struct DurabilityEntry: Sendable, Equatable {
    public let id: TransactionId

    /// Registration order. Monotonic, assigned by the store; recovery evaluates in this
    /// order so an entry consuming another's output is never decided before its
    /// predecessor.
    public var sequence: Int64

    public let inputs: [Input]
    public let outputs: [OwnAsset]

    /// Hash of the submitted extrinsic, captured by `SubmissionWatcher`. Rule 7 searches
    /// block bodies for it. A field, not a status — writing it is not a status change.
    public var txHash: Data?

    /// Finalized head read once immediately before registration. Rule 7's search window
    /// starts here, so no block below it can contain this extrinsic.
    public let checkpoint: BlockRef

    /// Blocks after `checkpoint` during which the extrinsic can still be included.
    public let mortality: UInt32

    /// Block where execution was first observed. Only ever written where success is
    /// already proven, so Rule 0 need only re-check that the block is still canonical.
    public var successDetectedAt: BlockRef?

    public var status: EntryStatus

    public let createdAt: Date

    public init(
        id: TransactionId = UUID(),
        sequence: Int64 = 0,
        inputs: [Input],
        outputs: [OwnAsset],
        txHash: Data? = nil,
        checkpoint: BlockRef,
        mortality: UInt32,
        successDetectedAt: BlockRef? = nil,
        status: EntryStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sequence = sequence
        self.inputs = inputs
        self.outputs = outputs
        self.txHash = txHash
        self.checkpoint = checkpoint
        self.mortality = mortality
        self.successDetectedAt = successDetectedAt
        self.status = status
        self.createdAt = createdAt
    }
}

extension DurabilityEntry: Operation_iOS.Identifiable {
    public var identifier: String {
        id.uuidString
    }
}

public extension DurabilityEntry {
    /// True when the extrinsic can no longer be included: `finalizedNumber` is past the last
    /// block of the entry's mortality window.
    ///
    /// Widened to `UInt64` so a checkpoint near `UInt32.max` cannot overflow into a false
    /// "window closed" and fail a live extrinsic.
    func isWindowClosed(atFinalized finalizedNumber: UInt32) -> Bool {
        UInt64(finalizedNumber) > UInt64(checkpoint.number) + UInt64(mortality)
    }
}
