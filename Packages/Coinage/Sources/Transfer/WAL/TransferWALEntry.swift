import Foundation
import SubstrateSdk
import Operation_iOS

/// Birth-block state for a WAL entry.
///
/// `.pending` until the extrinsic hash callback fires.
/// `.known` holds the block number and its hash together so they
/// are always consistent — no partial-update window between the two fields.
public enum CheckpointBlock: Sendable, Equatable {
    /// Block number and hash not yet captured — extrinsic not yet broadcast.
    case pending
    /// Block number and its hash at time of hash capture.
    /// Used for both mortality checks and fork detection on recovery.
    case known(number: UInt32, hash: Data)
}

/// Type of transfer operation tracked by a WAL entry.
///
/// Determines recovery logic in ``TransferRecoveryService``:
/// - `.intoCoins`: check expected output coins on-chain (existing behavior)
/// - `.intoExternalAsset`: verify input vouchers consumed on-chain (no output coins)
public enum TransferOperationType: Int, Sendable {
    case intoCoins = 0
    case intoExternalAsset = 1
}

/// "Write-Ahead Log" entry for a transfer extrinsic.
///
/// Persisted before extrinsic submission. Enables recovery on crash:
/// if the extrinsic confirmed on-chain but local DB write never ran,
/// recovery queries the chain and completes the DB write.
public struct TransferWALEntry: Sendable {
    /// Unique identifier for this WAL entry.
    public let id: UUID

    /// Type of transfer operation (determines recovery strategy).
    public let operationType: TransferOperationType

    /// Coin IDs of all input coins consumed by this extrinsic.
    /// Split: whole coins + overflow coin. Unload: empty (inputs are vouchers).
    /// Serialized as JSON array string.
    public let inputCoinIds: [String]

    /// Voucher IDs of all input vouchers consumed by this extrinsic.
    /// Split: empty (inputs are coins). Unload: all group vouchers.
    /// Serialized as JSON array string.
    public let inputVoucherIds: [String]

    /// Derivation indices of expected output coins.
    /// Split: change coins only. Unload into coins: recipient coins + change coins.
    /// External asset: empty (no output coins).
    /// Serialized as JSON array string.
    public let expectedCoinIndices: [UInt32]

    /// Derivation indices of expected surplus vouchers minted by the pallet.
    /// External asset with surplus: indices of new vouchers. All other types: empty.
    /// Used for on-chain recovery — vouchers are marked available once confirmed.
    /// Serialized as JSON array string.
    public let expectedVoucherIndices: [UInt32]

    /// Block number and hash captured when the `.created` status fires in `ExtrinsicSubmissionCoordinator`.
    /// `.pending` until that point.
    /// Used for mortality checks and fork detection on recovery.
    public let checkpointBlock: CheckpointBlock

    /// Maximum lifetime of extrinsic in blocks (pallet constant).
    /// Computed at submission time; if `finalizedBlock > checkpointBlock.number + mortality`,
    /// extrinsic is permanently dead.
    public let mortality: UInt32

    /// Timestamp of WAL entry creation.
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        operationType: TransferOperationType = .intoCoins,
        inputCoinIds: [String] = [],
        inputVoucherIds: [String] = [],
        expectedCoinIndices: [UInt32] = [],
        expectedVoucherIndices: [UInt32] = [],
        checkpointBlock: CheckpointBlock = .pending,
        mortality: UInt32,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.operationType = operationType
        self.inputCoinIds = inputCoinIds
        self.inputVoucherIds = inputVoucherIds
        self.expectedCoinIndices = expectedCoinIndices
        self.expectedVoucherIndices = expectedVoucherIndices
        self.checkpointBlock = checkpointBlock
        self.mortality = mortality
        self.createdAt = createdAt
    }
}

extension TransferWALEntry: Operation_iOS.Identifiable {
    public var identifier: String {
        id.uuidString
    }
}
