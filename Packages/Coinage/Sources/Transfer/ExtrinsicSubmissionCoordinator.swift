import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SDKLogger
import SubstrateOperation

/// Submits an extrinsic and writes its hash + checkpoint block into the WAL entry
/// so the recovery layer can scan for it if the app dies mid-flight.
protocol ExtrinsicSubmissionCoordinating {
    func submit(
        walEntryId: UUID,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> ExtrinsicMonitorSubmission
}

final class ExtrinsicSubmissionCoordinator: ExtrinsicSubmissionCoordinating {
    private let monitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let walStore: any TransferWALStoring
    private let blockNumberProvider: any BlockInfoProviding
    private let logger: SDKLoggerProtocol?

    init(
        monitor: ExtrinsicSubmitMonitorFactoryProtocol,
        walStore: any TransferWALStoring,
        blockNumberProvider: any BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.monitor = monitor
        self.walStore = walStore
        self.blockNumberProvider = blockNumberProvider
        self.logger = logger
    }

    func submit(
        walEntryId: UUID,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> ExtrinsicMonitorSubmission {
        // The checkpoint block is a recovery lower bound
        // "scan for this extrinsic starting from block N"
        // Fetching before submission guarantees the extrinsic cannot appear
        // in any block earlier than the checkpoint.
        let checkpointBlock = try await blockNumberProvider.fetchCurrent()
        let checkpointHash = try await blockNumberProvider.fetchBlockHash(checkpointBlock)

        // AsyncStream over AsyncExtensions alternatives:
        // - AsyncBufferedChannel: same semantics, only marginal API difference (send vs yield)
        // - AsyncPassthroughSubject: no buffering — risks dropping .create state before consumer task starts
        // - AsyncCurrentValueSubject: requires initial value + replays current; neither needed here
        let (stream, continuation) = AsyncStream<ExtrinsicStatusUpdate>.makeStream()

        let params = ExtrinsicSubmissionParams(
            feeAssetId: nil,
            eventsMatcher: nil
        ) { result in
            switch result {
            case let .success(update):
                continuation.yield(update)
            case .failure:
                continuation.finish()
            }
        }

        return try await withThrowingTaskGroup(
            of: ExtrinsicMonitorSubmission?.self
        ) { [walStore, monitor, logger] group -> ExtrinsicMonitorSubmission in
            group.addTask {
                defer { continuation.finish() }
                return try await monitor.submitAndMonitorWrapper(
                    extrinsicBuilderClosure: builder,
                    origin: origin,
                    params: params
                )
                .asyncExecute()
            }

            // Extrinsic state observation
            group.addTask {
                for await update in stream {
                    guard case .created = update.extrinsicStatus else {
                        continue
                    }
                    do {
                        try await walStore.update(
                            id: walEntryId,
                            checkpointBlock: .known(
                                number: checkpointBlock,
                                hash: checkpointHash
                            )
                        )
                    } catch {
                        logger?.error("WAL update failed for \(walEntryId): \(error)")
                    }
                    break
                }
                return nil
            }

            var result: ExtrinsicMonitorSubmission?
            for try await value in group {
                if let value { result = value }
            }
            guard let result else {
                throw TransferStrategyError.submissionFailed(CancellationError())
            }
            return result
        }
    }
}
