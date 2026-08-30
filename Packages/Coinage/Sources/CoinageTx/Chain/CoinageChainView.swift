import Foundation
import KeyDerivation
import SubstrateOperation

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

/// Outcome of looking one extrinsic hash up in one block.
///
/// `unreadable` is never proof of absence — only `notInBlock` is, and only because the block
/// was read in full.
enum BlockLookup {
    case unreadable
    case notInBlock
    case outcome(ReadResult<Bool>)
}

/// Reads one extrinsic hash's dispatch outcome from one block. The single access that needs a
/// live connection and runtime metadata, injected as a closure so the window-scan logic in
/// ``BlockBodyScan`` can be exercised without either.
typealias BlockOutcomeLookup = @Sendable (_ txHash: Data, _ blockHash: Data) async -> BlockLookup

/// Resolves a block hash to its number via a direct `chain_getHeader` RPC (Android `blockNumberAt`),
/// returning `nil` when the read failed. Injected so the view needs no connection of its own.
typealias BlockNumberByHash = @Sendable (_ blockHash: Data) async -> UInt32?

/// Three-valued chain access for the durability engine.
///
/// Every method returns `failedRead` rather than throwing on transport failure, an unknown
/// block, a key missing from a batched response, or an undecodable value, so a read failure
/// can never be mistaken for absence. Mirrors Android's `CoinageChainView`.
public protocol CoinageChainViewProtocol: Sendable {
    /// The finalized head this view is pinned to. Every read the pass makes is evaluated
    /// against this and ``bestHead``.
    var finalizedHead: BlockRef { get }

    /// The best head this view is pinned to.
    var bestHead: BlockRef { get }

    /// Presence of each input at `block`, in the order given.
    func readInputs(_ inputs: [CoinageTxInput], at block: BlockRef) async -> [ReadResult<AssetPresence>]

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

/// Concrete ``CoinageChainViewProtocol`` — the consolidation of the former `DurabilityChainReader`
/// (asset/head reads) and `BlockBodySearcher`/`BlockDataReading` (body scan) into one type.
///
/// Wraps the coin and voucher queries and converts every failure mode — a transport error, an
/// unknown block, a short batched response, an undecodable value — into `failedRead` rather than
/// `absent`, so no read failure can ever produce a terminal verdict.
final class CoinageChainView: CoinageChainViewProtocol, @unchecked Sendable {
    let finalizedHead: BlockRef
    let bestHead: BlockRef

    private let coinQuery: any CoinOnChainQuerying
    private let voucherQuery: any VoucherOnChainQuerying
    private let blockInfoProvider: any BlockInfoProviding
    private let blockNumberByHash: BlockNumberByHash
    private let scan: BlockBodyScan

    init(
        checkpoints: ChainView,
        coinQuery: any CoinOnChainQuerying,
        voucherQuery: any VoucherOnChainQuerying,
        blockInfoProvider: any BlockInfoProviding,
        blockNumberByHash: @escaping BlockNumberByHash,
        blockOutcome: @escaping BlockOutcomeLookup
    ) {
        finalizedHead = checkpoints.finalized
        bestHead = checkpoints.best
        self.coinQuery = coinQuery
        self.voucherQuery = voucherQuery
        self.blockInfoProvider = blockInfoProvider
        self.blockNumberByHash = blockNumberByHash
        scan = BlockBodyScan(blockOutcome: blockOutcome, blockInfoProvider: blockInfoProvider)
    }
}

// MARK: - Heads and body scan

extension CoinageChainView {
    func blockHash(at number: UInt32) async -> ReadResult<Data> {
        guard let hash = try? await blockInfoProvider.fetchBlockHash(number) else {
            return .failedRead
        }
        return .present(hash)
    }

    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef> {
        guard let number = await blockNumberByHash(hash) else { return .failedRead }
        return .present(BlockRef(number: number, hash: hash))
    }

    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        await scan.outcome(of: txHash, at: block)
    }

    func searchBodies(for txHash: Data, in window: ClosedRange<UInt32>) async -> BodySearchOutcome {
        await scan.search(for: txHash, in: window)
    }
}

// MARK: - Asset reads

extension CoinageChainView {
    func readInputs(_ inputs: [CoinageTxInput], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        await read(assets: inputs.map(AssetQuery.init(input:)), at: block)
    }

    func readOutputs(_ outputs: [OwnAsset], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        await read(assets: outputs.map { AssetQuery(input: $0.asInput) }, at: block)
    }
}

private extension CoinageChainView {
    /// One asset to read, in its original position so results can be returned in order.
    struct AssetQuery {
        let input: CoinageTxInput
    }

    /// A coin whose key cannot be derived is left out of both batches, so its position keeps
    /// the `failedRead` it starts with.
    func read(assets: [AssetQuery], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        guard !assets.isEmpty else { return [] }

        let coins = assets.enumerated().compactMap { position, asset -> (position: Int, key: Data)? in
            asset.input.isCoin ? (position, asset.input.publicKey) : nil
        }

        let vouchers = assets.enumerated().compactMap { position, asset -> (position: Int, index: DerivationIndex)? in
            guard case let .recyclerVoucher(index, _) = asset.input else { return nil }
            return (position, index)
        }

        async let coinReads = fetchCoins(keys: coins.map(\.key), at: block)
        async let voucherReads = fetchVouchers(indices: vouchers.map(\.index), at: block)

        let (coinResults, voucherResults) = await (coinReads, voucherReads)

        var results = [ReadResult<AssetPresence>](repeating: .failedRead, count: assets.count)
        for (asset, result) in zip(coins, coinResults) {
            results[asset.position] = result
        }
        for (asset, result) in zip(vouchers, voucherResults) {
            results[asset.position] = result
        }

        return results
    }

    /// Batched coin read. A response shorter than the request means a key is missing from it,
    /// which the spec requires be treated as no verdict rather than absence.
    func fetchCoins(keys: [Data], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        guard !keys.isEmpty else { return [] }

        guard let responses = try? await coinQuery.fetchCoins(
            for: keys,
            atBlockHash: block.hash
        ), responses.count == keys.count
        else {
            return Array(repeating: .failedRead, count: keys.count)
        }

        return responses.map { $0 == nil ? .absent : .present(AssetPresence()) }
    }

    func fetchVouchers(
        indices: [DerivationIndex],
        at block: BlockRef
    ) async -> [ReadResult<AssetPresence>] {
        guard !indices.isEmpty else { return [] }

        guard let responses = try? await voucherQuery.fetchVouchers(
            for: indices,
            atBlockHash: block.hash
        ), responses.count == indices.count else {
            return Array(repeating: .failedRead, count: indices.count)
        }

        return responses.map { info in
            guard let info else { return .absent }
            return .present(AssetPresence(isUnloaded: info.isUnloaded))
        }
    }
}

// MARK: - Body scan

/// Scans block bodies for an extrinsic hash and reads its dispatch outcome.
///
/// Rule 7's evidence of last resort: used when no output, input or recorded inclusion could
/// decide an entry. Nothing is carried between passes — a pass that cannot read the whole
/// window simply repeats it, which is the same liveness either way, and the window is bounded
/// at one mortality.
struct BlockBodyScan {
    let blockOutcome: BlockOutcomeLookup
    let blockInfoProvider: any BlockInfoProviding

    /// Scans `window` for `txHash`, newest block first so a recent inclusion is found quickly.
    ///
    /// On a hit the dispatch outcome is read from the same block the extrinsic was found in —
    /// inclusion is not success, and only the events at that block say which.
    func search(for txHash: Data, in window: ClosedRange<UInt32>) async -> BodySearchOutcome {
        var everyBlockRead = true

        for number in window.reversed() {
            guard let hash = try? await blockInfoProvider.fetchBlockHash(number) else {
                everyBlockRead = false
                continue
            }

            let block = BlockRef(number: number, hash: hash)

            switch await blockOutcome(txHash, hash) {
            case .unreadable:
                everyBlockRead = false
            case .notInBlock:
                continue
            case let .outcome(result):
                return mapSearchOutcome(result: result, block: block)
            }
        }

        return everyBlockRead ? .notFoundWindowComplete : .incomplete
    }

    /// Reads the outcome of `txHash` at `block`, resolving its index from the same block the
    /// events come from.
    func outcome(of txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        switch await blockOutcome(txHash, block.hash) {
        case let .outcome(result):
            result
        case .notInBlock,
             .unreadable:
            .failedRead
        }
    }

    private func mapSearchOutcome(result: ReadResult<Bool>, block: BlockRef) -> BodySearchOutcome {
        switch result {
        case .present(true):
            .foundSucceeded(block)
        case .present(false):
            .foundFailed(block)
        case .absent,
             .failedRead:
            .foundOutcomeUnreadable(block)
        }
    }
}
