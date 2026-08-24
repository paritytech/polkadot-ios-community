import Foundation
@preconcurrency import SDKLogger
@preconcurrency import SubstrateOperation

/// Scans block bodies for an extrinsic hash and reads its dispatch outcome.
///
/// Rule 7's evidence of last resort: used when no output, input or recorded inclusion could
/// decide an entry. Nothing is carried between passes — a pass that cannot read the whole
/// window simply repeats it, which is the same liveness either way, and the window is bounded
/// at one mortality.
final class BlockBodySearcher: Sendable {
    private let blockData: any BlockDataReading
    private let blockInfoProvider: any BlockInfoProviding
    private let logger: SDKLoggerProtocol?

    init(
        blockData: any BlockDataReading,
        blockInfoProvider: any BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.blockData = blockData
        self.blockInfoProvider = blockInfoProvider
        self.logger = logger
    }

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

            switch await blockData.lookUp(txHash, at: hash) {
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
        switch await blockData.lookUp(txHash, at: block.hash) {
        case let .outcome(result):
            result
        case .notInBlock,
             .unreadable:
            .failedRead
        }
    }
}

// MARK: - Private

private extension BlockBodySearcher {
    func mapSearchOutcome(result: ReadResult<Bool>, block: BlockRef) -> BodySearchOutcome {
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
