import Foundation
import Operation_iOS
@preconcurrency import SubstrateSdk
@preconcurrency import ExtrinsicService
import StructuredConcurrency
import SubstrateOperation

/// Outcome of looking one extrinsic hash up in one block.
///
/// `unreadable` is never proof of absence — only `notInBlock` is, and only because the block
/// was read in full.
enum BlockLookup {
    case unreadable
    case notInBlock
    case outcome(ReadResult<Bool>)
}

/// The single block read ``BlockBodySearcher`` performs.
///
/// Isolates the one access that needs a live connection and runtime metadata, so the
/// searcher's window logic can be exercised without either.
protocol BlockDataReading: Sendable {
    /// Looks `txHash` up in the block at `blockHash` and, on a hit, resolves its dispatch
    /// outcome from that same block's events.
    func lookUp(_ txHash: Data, at blockHash: Data) async -> BlockLookup
}

final class BlockDataReader: BlockDataReading {
    private let connection: any JSONRPCEngine
    private let runtimeService: any RuntimeCodingServiceProtocol
    private let eventsQueryFactory: any BlockEventsQueryFactoryProtocol

    init(
        connection: any JSONRPCEngine,
        runtimeService: any RuntimeCodingServiceProtocol,
        eventsQueryFactory: any BlockEventsQueryFactoryProtocol
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.eventsQueryFactory = eventsQueryFactory
    }

    func lookUp(_ txHash: Data, at blockHash: Data) async -> BlockLookup {
        guard let blockDetails = try? await queryBlockDetails(blockHash: blockHash) else {
            return .unreadable
        }

        guard let extrinsic = findExtrinsic(txHash: txHash, in: blockDetails) else {
            return .notInBlock
        }

        return await resolveOutcome(extrinsic: extrinsic)
    }
}

// MARK: - Private

private extension BlockDataReader {
    func queryBlockDetails(blockHash: Data) async throws -> SubstrateBlockDetails {
        let wrapper = eventsQueryFactory.queryBlockDetailsWrapper(
            from: connection,
            runtimeProvider: runtimeService,
            blockHash: blockHash
        )
        return try await wrapper.asyncExecute()
    }

    func findExtrinsic(
        txHash: Data,
        in blockDetails: SubstrateBlockDetails
    ) -> SubstrateExtrinsicEvents? {
        blockDetails.extrinsicsWithEvents.first { $0.extrinsicHash == txHash }
    }

    func resolveOutcome(extrinsic: SubstrateExtrinsicEvents) async -> BlockLookup {
        guard let coderFactory = try? await runtimeService.fetchCoderFactoryOperation()
            .asyncExecute() else {
            return .outcome(.failedRead)
        }

        let successMatcher = ExtrinsicSuccessEventMatcher()
        let failureMatcher = ExtrinsicFailureEventMatcher()

        for record in extrinsic.eventRecords {
            if successMatcher.match(event: record.event, using: coderFactory) {
                return .outcome(.present(true))
            }
            if failureMatcher.match(event: record.event, using: coderFactory) {
                return .outcome(.present(false))
            }
        }

        // Applied, but neither outcome event is present — the block was read and still says
        // nothing, so this decides nothing.
        return .outcome(.failedRead)
    }
}
