import Coinage
import Foundation

/// A test fake for `DurabilityChainReading` that allows per-key, per-block response
/// configuration.
///
/// Default behaviour for any unconfigured read is `absent`; tests must opt in to
/// presence. Serves a pinned `ChainView` that the test sets.
actor FakeChainView: DurabilityChainReading {
    private var pinnedView: ChainView
    private var inputResults: [UInt32: [ReadResult<AssetPresence>]] = [:]
    private var outputResults: [UInt32: [ReadResult<AssetPresence>]] = [:]
    private var hashResults: [UInt32: ReadResult<Data>] = [:]
    private var refResults: [Data: ReadResult<BlockRef>] = [:]
    private var outcomeResults: [UInt32: [Data: ReadResult<Bool>]] = [:]
    private var bodySearchResponses: [Data: BodySearchOutcome] = [:]
    private var connectionValid = true

    init(
        finalized: BlockRef = BlockRef(number: 100, hash: Data([100])),
        best: BlockRef = BlockRef(number: 110, hash: Data([110]))
    ) {
        pinnedView = ChainView(
            finalized: finalized,
            best: best,
            connectionToken: UUID()
        )
    }

    // MARK: - Configuration API

    func setChainView(finalized: BlockRef, best: BlockRef) {
        pinnedView = ChainView(
            finalized: finalized,
            best: best,
            connectionToken: pinnedView.connectionToken
        )
    }

    func setInputPresence(
        at block: BlockRef,
        to results: [ReadResult<AssetPresence>]
    ) {
        inputResults[block.number] = results
    }

    func setOutputPresence(
        at block: BlockRef,
        to results: [ReadResult<AssetPresence>]
    ) {
        outputResults[block.number] = results
    }

    func setBlockHash(_ hash: Data, forNumber number: UInt32) {
        hashResults[number] = .present(hash)
    }

    func setBlockHashFailed(_ number: UInt32) {
        hashResults[number] = .failedRead
    }

    func setBlockRef(_ ref: BlockRef) {
        refResults[ref.hash] = .present(ref)
    }

    func setBlockRefFailed(_ hash: Data) {
        refResults[hash] = .failedRead
    }

    func setDispatchOutcome(_ txHash: Data, at block: BlockRef, success: Bool) {
        outcomeResults[block.number, default: [:]][txHash] = .present(success)
    }

    func setDispatchOutcomeFailed(_ txHash: Data, at block: BlockRef) {
        outcomeResults[block.number, default: [:]][txHash] = .failedRead
    }

    func setBodySearchResponse(_ txHash: Data, to outcome: BodySearchOutcome) {
        bodySearchResponses[txHash] = outcome
    }

    func invalidateConnection() {
        connectionValid = false
    }

    // MARK: - DurabilityChainReading

    func pinChainView() async throws -> ChainView {
        pinnedView
    }

    func isCurrent(_ view: ChainView) async -> Bool {
        connectionValid && view.connectionToken == pinnedView.connectionToken
    }

    func readInputs(
        _ inputs: [Input],
        at block: BlockRef
    ) async -> [ReadResult<AssetPresence>] {
        inputResults[block.number] ?? Array(repeating: .absent, count: inputs.count)
    }

    func readOutputs(
        _ outputs: [OwnAsset],
        at block: BlockRef
    ) async -> [ReadResult<AssetPresence>] {
        outputResults[block.number] ?? Array(repeating: .absent, count: outputs.count)
    }

    func blockHash(at number: UInt32) async -> ReadResult<Data> {
        hashResults[number] ?? .absent
    }

    func blockRef(forHash hash: Data) async -> ReadResult<BlockRef> {
        refResults[hash] ?? .absent
    }

    func dispatchOutcome(txHash: Data, at block: BlockRef) async -> ReadResult<Bool> {
        (outcomeResults[block.number] ?? [:])[txHash] ?? .absent
    }

    func searchBodies(
        for txHash: Data,
        in _: ClosedRange<UInt32>
    ) async -> BodySearchOutcome {
        bodySearchResponses[txHash] ?? .notFoundWindowComplete
    }
}
