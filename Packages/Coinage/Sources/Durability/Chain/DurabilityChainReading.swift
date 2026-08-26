import Foundation

/// On-chain presence of one asset at one block.
///
/// `isUnloaded` is meaningful only for recycler vouchers: a successful unload marks the alias
/// without removing the recycler mapping, so a spent voucher can still read present.
public struct AssetPresence: Sendable, Equatable {
    public let isUnloaded: Bool

    public init(isUnloaded: Bool = false) {
        self.isUnloaded = isUnloaded
    }
}

/// Result of scanning the mortality window for an extrinsic hash.
public enum BodySearchOutcome: Sendable, Equatable {
    case foundSucceeded(BlockRef)
    case foundFailed(BlockRef)
    /// Included, but the events at that block could not be decoded.
    case foundOutcomeUnreadable(BlockRef)
    /// Every block in the window was read and the hash is in none of them.
    case notFoundWindowComplete
    /// At least one block in the window could not be read, so the search decided nothing.
    case incomplete
}

/// Three-valued chain access for the durability engine.
///
/// Every method returns `failedRead` rather than throwing on transport failure, an unknown
/// block, a key missing from a batched response, or an undecodable value, so a read failure
/// can never be mistaken for absence.
public protocol DurabilityChainReading: Sendable {
    /// Reads the finalized and best heads from one connection and asserts the best head
    /// descends from the finalized one.
    func pinChainView() async throws -> ChainView

    /// True while the connection backing `view` is still the current one.
    func isCurrent(_ view: ChainView) async -> Bool

    /// Presence of each input at `block`, in the order given.
    func readInputs(_ inputs: [DurabilityInput], at block: BlockRef) async -> [ReadResult<AssetPresence>]

    /// Presence of each output at `block`, in the order given.
    func readOutputs(_ outputs: [OwnAsset], at block: BlockRef) async -> [ReadResult<AssetPresence>]

    /// Canonical hash at a block number.
    func blockHash(at number: UInt32) async -> ReadResult<Data>

    /// Resolves a block hash to a full ``BlockRef``.
    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef>

    /// Reads the dispatch outcome of `txHash` from the events at `block`.
    /// `present(true)` is `ExtrinsicSuccess`, `present(false)` is `ExtrinsicFailure`.
    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool>

    /// Scans `window` for `txHash` and, on a hit, reads the dispatch outcome from the same
    /// block the extrinsic was found in.
    func searchBodies(for txHash: Data, in window: ClosedRange<UInt32>) async -> BodySearchOutcome
}
