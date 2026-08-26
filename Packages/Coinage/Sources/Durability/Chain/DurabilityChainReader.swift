import Foundation
import Operation_iOS
import SubstrateSdk
import KeyDerivation
import StructuredConcurrency
import SubstrateOperation
import SDKLogger

/// Three-valued chain access for the durability engine.
///
/// Wraps the existing coin and voucher queries and converts every failure mode — a transport
/// error, an unknown block, a short batched response, an undecodable value — into
/// `failedRead` rather than `absent`, so no read failure can ever produce a terminal verdict.
final class DurabilityChainReader: @unchecked Sendable {
    private let coinQuery: any CoinOnChainQuerying
    private let voucherQuery: any VoucherOnChainQuerying
    private let coinKeyFactory: any CoinKeyDeriving
    private let blockInfoProvider: any BlockInfoProviding
    private let searcher: BlockBodySearcher
    private let connectionToken: UUID
    private let logger: SDKLoggerProtocol?

    init(
        coinQuery: any CoinOnChainQuerying,
        voucherQuery: any VoucherOnChainQuerying,
        coinKeyFactory: any CoinKeyDeriving,
        blockInfoProvider: any BlockInfoProviding,
        searcher: BlockBodySearcher,
        logger: SDKLoggerProtocol?
    ) {
        self.coinQuery = coinQuery
        self.voucherQuery = voucherQuery
        self.coinKeyFactory = coinKeyFactory
        self.blockInfoProvider = blockInfoProvider
        self.searcher = searcher
        connectionToken = UUID()
        self.logger = logger
    }
}

// MARK: - DurabilityChainReading

extension DurabilityChainReader: DurabilityChainReading {
    /// Reads both heads and asserts the best head is at or above the finalized one.
    ///
    /// The assertion is the reachable form of "B descends from F": the two are read from one
    /// injected connection, so a best head below finality means the peer is inconsistent and
    /// the pass must not run against it.
    func pinChainView() async throws -> ChainView {
        let finalizedNumber = try await blockInfoProvider.fetchFinalized()
        let finalizedHash = try await blockInfoProvider.fetchBlockHash(finalizedNumber)
        let bestNumber = try await blockInfoProvider.fetchCurrent()
        let bestHash = try await blockInfoProvider.fetchBlockHash(bestNumber)

        guard bestNumber >= finalizedNumber else {
            throw DurabilityError.chainViewUnavailable
        }

        return ChainView(
            finalized: BlockRef(number: finalizedNumber, hash: finalizedHash),
            best: BlockRef(number: bestNumber, hash: bestHash),
            connectionToken: connectionToken
        )
    }

    /// The connection is injected once and held for this reader's lifetime, so the token is
    /// stable. A reconnect inside the engine is not observable through this API; a genuine
    /// connection swap means a new reader and therefore a new token, which is what a pass
    /// holding the old view detects.
    func isCurrent(_ view: ChainView) async -> Bool {
        view.connectionToken == connectionToken
    }

    func readInputs(_ inputs: [DurabilityInput], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        await read(assets: inputs.map(AssetQuery.init(input:)), at: block)
    }

    func readOutputs(_ outputs: [OwnAsset], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        await read(assets: outputs.map { AssetQuery(input: $0.asInput) }, at: block)
    }

    func blockHash(at number: UInt32) async -> ReadResult<Data> {
        guard let hash = try? await blockInfoProvider.fetchBlockHash(number) else {
            return .failedRead
        }
        return .present(hash)
    }

    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef> {
        guard let number = await blockNumber(forHash: hash) else { return .failedRead }
        return .present(BlockRef(number: number, hash: hash))
    }

    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        await searcher.outcome(of: txHash, at: block)
    }

    func searchBodies(for txHash: Data, in window: ClosedRange<UInt32>) async -> BodySearchOutcome {
        await searcher.search(for: txHash, in: window)
    }
}

// MARK: - Asset reads

private extension DurabilityChainReader {
    /// One asset to read, in its original position so results can be returned in order.
    struct AssetQuery {
        let input: DurabilityInput
    }

    /// A coin whose key cannot be derived is left out of both batches, so its position keeps
    /// the `failedRead` it starts with.
    func read(assets: [AssetQuery], at block: BlockRef) async -> [ReadResult<AssetPresence>] {
        guard !assets.isEmpty else { return [] }

        let coins = assets.enumerated().compactMap { position, asset -> (position: Int, key: Data)? in
            switch asset.input {
            case let .coin(.own(index)):
                (try? coinKeyFactory.derivePublicKey(placeholderIndex: index))
                    .map { (position, $0) }
            case let .coin(.received(publicKey)):
                (position, publicKey)
            case .recyclerVoucher:
                nil
            }
        }

        let vouchers = assets.enumerated().compactMap { position, asset -> (position: Int, index: DerivationIndex)? in
            guard case let .recyclerVoucher(index) = asset.input else { return nil }
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

    func blockNumber(forHash hash: Data) async -> UInt32? {
        // The finalized-head subscription is the only header source the block provider
        // exposes, so the number is recovered by matching the hash against the canonical
        // chain around the current head rather than by a direct header fetch.
        guard let current = try? await blockInfoProvider.fetchCurrent() else { return nil }

        for candidate in stride(from: Int(current), through: max(Int(current) - 64, 0), by: -1) {
            guard let candidateHash = try? await blockInfoProvider
                .fetchBlockHash(UInt32(candidate))
            else { continue }
            if candidateHash == hash { return UInt32(candidate) }
        }

        return nil
    }
}
