import Foundation
@preconcurrency import ExtrinsicService
import SubstrateSdk
@preconcurrency import SDKLogger
import BackgroundExecution
import StructuredConcurrency

/// A registered entry together with the submission tracking it.
public struct CoinageTxSubmission {
    public let transactionId: CoinageTxId
    public let submission: ExtrinsicMonitorSubmission

    public init(transactionId: CoinageTxId, submission: ExtrinsicMonitorSubmission) {
        self.transactionId = transactionId
        self.submission = submission
    }
}

/// Submits an entry's extrinsic and follows it until there is nothing left to learn.
///
/// Ownership is one-shot. The entry is taken by ``CoinageTxRegistrar`` before submission and
/// released here exactly once — never re-taken, including after a resubmission — so a recovery
/// pass and a live submission can never both be deciding the same entry.
///
/// While it owns the entry the tracker writes only evidence — `txHash` and `successDetectedAt` —
/// never the status: the recovery pass skips watched entries, so the tracker is the sole writer
/// but leaves the verdict to the pass, which finishes the entry after release with full evidence.
/// Those field writes are what Rule 0 and Rule 7 read.
final class CoinageTxTracker: Sendable {
    private let monitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let store: any CoinageTxRepositoryProtocol
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let watched: CoinageTrackingTxSet
    private let backgroundExecutor: any BackgroundExecuting
    private let onRelease: @Sendable () -> Void
    private let logger: SDKLoggerProtocol?

    /// Longest gap between status updates before the entry is handed back to the pass.
    private static let silenceTimeout: Duration = .seconds(30)

    /// A dropped or invalid extrinsic is resubmitted at most this many times before release.
    private static let maxResubmissions = 1

    init(
        monitor: ExtrinsicSubmitMonitorFactoryProtocol,
        store: any CoinageTxRepositoryProtocol,
        chainFactory: any CoinageChainViewFactoryProtocol,
        watched: CoinageTrackingTxSet,
        backgroundExecutor: any BackgroundExecuting,
        onRelease: @escaping @Sendable () -> Void,
        logger: SDKLoggerProtocol?
    ) {
        self.monitor = monitor
        self.store = store
        self.chainFactory = chainFactory
        self.watched = watched
        self.backgroundExecutor = backgroundExecutor
        self.onRelease = onRelease
        self.logger = logger
    }

    /// Fire-and-forget submission: submits and tracks the extrinsic in a detached task, holding a
    /// background-task assertion (via `backgroundExecutor`) so tracking survives the app being
    /// folded. Ownership is released when tracking ends; the result is not surfaced to the caller.
    func watch(
        entryId: CoinageTxId,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) {
        Task { [self] in
            do {
                try await backgroundExecutor.execute {
                    try await markStallActivity("Coinage submission") {
                        try await markStallRegion("Track extrinsic") {
                            _ = try await self.submit(entryId: entryId, builder: builder, origin: origin)
                        }
                    }
                }
            } catch {
                logger?.error("Background submission failed for \(entryId): \(error)")
            }
        }
    }

    /// Submits the entry's extrinsic and tracks it to completion.
    ///
    /// The caller has already registered the entry, so ownership is held on entry to this
    /// method and given up before it returns.
    func submit(
        entryId: CoinageTxId,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> CoinageTxSubmission {
        defer { release(entryId) }

        let (stream, continuation) = AsyncStream<ExtrinsicStatusUpdate>.makeStream()

        let params = ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil) { result in
            switch result {
            case let .success(update):
                continuation.yield(update)
            case .failure:
                continuation.finish()
            }
        }

        return try await withThrowingTaskGroup(
            of: ExtrinsicMonitorSubmission?.self
        ) { [monitor] group -> CoinageTxSubmission in
            group.addTask {
                defer { continuation.finish() }
                return try await monitor.submitAndMonitorWrapper(
                    extrinsicBuilderClosure: builder,
                    origin: origin,
                    params: params
                )
                .asyncExecute()
            }

            group.addTask { [weak self] in
                await self?.follow(stream: stream, entryId: entryId)
                return nil
            }

            var result: ExtrinsicMonitorSubmission?
            for try await value in group {
                if let value { result = value }
            }
            guard let result else {
                throw TransferStrategyError.submissionFailed(CancellationError())
            }
            return CoinageTxSubmission(transactionId: entryId, submission: result)
        }
    }
}

// MARK: - Following

private extension CoinageTxTracker {
    /// Consumes status updates until the stream ends or falls silent past the timeout.
    func follow(stream: AsyncStream<ExtrinsicStatusUpdate>, entryId: CoinageTxId) async {
        var hashRecorded = false

        await consume(stream, idleTimeout: Self.silenceTimeout) { update in
            if !hashRecorded, let txHash = try? Data(hexString: update.extrinsicHash) {
                try? await self.store.recordTxHash(entryId, txHash: txHash)
                hashRecorded = true
            }

            return await self.handle(update, entryId: entryId)
        }
    }

    /// Maps one status update onto the entry. Returns true when tracking should stop.
    func handle(_ update: ExtrinsicStatusUpdate, entryId: CoinageTxId) async -> Bool {
        guard case let .onChain(remote) = update.extrinsicStatus else {
            // `.created` carries no chain information.
            return false
        }

        switch remote {
        case .future,
             .ready,
             .broadcast:
            // Pre-inclusion: nothing on chain yet. The recovery pass owns the status; the tracker
            // only records evidence (txHash above, and inclusion below).
            return false

        case let .inBlock(blockHash):
            await handleInBlock(blockHash: blockHash, update: update, entryId: entryId)
            return false

        case let .retracted(blockHash):
            await handleRetracted(blockHash: blockHash, entryId: entryId)
            return false

        case let .finalized(blockHash):
            await handleFinalized(blockHash: blockHash, update: update, entryId: entryId)
            return true

        case .dropped,
             .invalid:
            // Best-effort only, and capped: the entry may still be in another peer's pool, so
            // the pass — not this watcher — is what decides it.
            return true

        case .unsurped,
             .finalityTimeout,
             .other:
            return true
        }
    }

    /// An inclusion in an unfinalized block. Success there is recorded as evidence, because
    /// nothing else can see it once a peer claims the output; a failed or unreadable dispatch
    /// records nothing and proposes nothing, so no terminal status ever rests on this block.
    func handleInBlock(
        blockHash: String,
        update: ExtrinsicStatusUpdate,
        entryId: CoinageTxId
    ) async {
        guard let view = try? await chainFactory.pin(),
              let block = await resolveBlock(blockHash, using: view),
              let txHash = try? Data(hexString: update.extrinsicHash)
        else { return }

        guard case let .present(succeeded) = await view.dispatchOutcome(txHash: txHash, at: block)
        else { return }

        guard succeeded else { return }

        // Record the block where inclusion succeeded — evidence Rule 0 needs. The pass promotes the
        // status; this write is what lets it decide the entry later without re-deriving execution.
        try? await store.recordSuccessDetected(entryId, at: block)
    }

    /// The block an inclusion was recorded in is gone. The record is cleared only when it
    /// names that block — a later inclusion elsewhere must survive.
    func handleRetracted(blockHash: String, entryId: CoinageTxId) async {
        guard let hash = try? Data(hexString: blockHash),
              let entry = try? await store.fetch(id: entryId),
              let detected = entry.successDetectedAt,
              detected.hash == hash
        else { return }

        try? await store.recordSuccessDetected(entryId, at: nil)
    }

    func handleFinalized(
        blockHash: String,
        update: ExtrinsicStatusUpdate,
        entryId: CoinageTxId
    ) async {
        guard let view = try? await chainFactory.pin(),
              let block = await resolveBlock(blockHash, using: view),
              let txHash = try? Data(hexString: update.extrinsicHash)
        else { return }

        switch await view.dispatchOutcome(txHash: txHash, at: block) {
        case .present(true):
            // Record the finalized success block; the pass reads it and promotes the entry.
            try? await store.recordSuccessDetected(entryId, at: block)
        case .present(false),
             .absent,
             .failedRead:
            // Failure or unreadable outcome: record nothing and let the pass decide from state.
            break
        }
    }

    func resolveBlock(_ blockHash: String, using view: any CoinageChainViewProtocol) async -> BlockRef? {
        guard let hash = try? Data(hexString: blockHash) else { return nil }
        return await view.blockRef(forHash: hash).value
    }

    /// Releases ownership once and triggers a pass, so the entry is picked up immediately
    /// rather than waiting for the next external trigger.
    func release(_ entryId: CoinageTxId) {
        guard watched.release(entryId) else { return }
        onRelease()
    }
}
