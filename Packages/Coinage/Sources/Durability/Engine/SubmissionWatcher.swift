import Foundation
@preconcurrency import ExtrinsicService
import SubstrateSdk
@preconcurrency import SDKLogger
import BackgroundExecution
import StructuredConcurrency

/// A registered entry together with the submission tracking it.
public struct DurabilitySubmission {
    public let transactionId: TransactionId
    public let submission: ExtrinsicMonitorSubmission

    public init(transactionId: TransactionId, submission: ExtrinsicMonitorSubmission) {
        self.transactionId = transactionId
        self.submission = submission
    }
}

/// Submits an entry's extrinsic and follows it until there is nothing left to learn.
///
/// Ownership is one-shot. The entry is taken by ``EntryRegistrar`` before submission and
/// released here exactly once — never re-taken, including after a resubmission — so a recovery
/// pass and a live submission can never both be deciding the same entry.
///
/// Every status the watcher derives is routed through ``StatusUpdateTransaction``, which
/// declines proposals for a watched entry; since this watcher holds the entry for as long as
/// it is proposing, those proposals are all no-ops. That is the spec as written. What does
/// land are the field writes — `txHash` and `successDetectedAt` — which are not status changes
/// and so are not declined. They are what Rule 0 and Rule 7 need, so the pass can finish the
/// entry after release with full evidence.
final class SubmissionWatcher: Sendable {
    private let monitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let store: any CoinageTxRepositoryProtocol
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let watched: WatchedEntrySet
    private let transaction: StatusUpdateTransaction
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
        watched: WatchedEntrySet,
        transaction: StatusUpdateTransaction,
        backgroundExecutor: any BackgroundExecuting,
        onRelease: @escaping @Sendable () -> Void,
        logger: SDKLoggerProtocol?
    ) {
        self.monitor = monitor
        self.store = store
        self.chainFactory = chainFactory
        self.watched = watched
        self.transaction = transaction
        self.backgroundExecutor = backgroundExecutor
        self.onRelease = onRelease
        self.logger = logger
    }

    /// Fire-and-forget submission: submits and tracks the extrinsic in a detached task, holding a
    /// background-task assertion (via `backgroundExecutor`) so tracking survives the app being
    /// folded. Ownership is released when tracking ends; the result is not surfaced to the caller.
    func watch(
        entryId: TransactionId,
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
        entryId: TransactionId,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission {
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
        ) { [monitor] group -> DurabilitySubmission in
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
            return DurabilitySubmission(transactionId: entryId, submission: result)
        }
    }
}

// MARK: - Following

private extension SubmissionWatcher {
    /// Consumes status updates until the stream ends or falls silent past the timeout.
    func follow(stream: AsyncStream<ExtrinsicStatusUpdate>, entryId: TransactionId) async {
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
    func handle(_ update: ExtrinsicStatusUpdate, entryId: TransactionId) async -> Bool {
        guard case let .onChain(remote) = update.extrinsicStatus else {
            // `.created` carries no chain information.
            return false
        }

        switch remote {
        case .future,
             .ready,
             .broadcast:
            await propose(.status(.pending), to: entryId)
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
        entryId: TransactionId
    ) async {
        guard let view = try? await chainFactory.pin(),
              let block = await resolveBlock(blockHash, using: view),
              let txHash = try? Data(hexString: update.extrinsicHash)
        else { return }

        guard case let .present(succeeded) = await view.dispatchOutcome(txHash: txHash, at: block)
        else { return }

        guard succeeded else { return }

        try? await store.recordSuccessDetected(entryId, at: block)
        await propose(.status(.pendingSuccess), to: entryId)
    }

    /// The block an inclusion was recorded in is gone. The record is cleared only when it
    /// names that block — a later inclusion elsewhere must survive.
    func handleRetracted(blockHash: String, entryId: TransactionId) async {
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
        entryId: TransactionId
    ) async {
        guard let view = try? await chainFactory.pin(),
              let block = await resolveBlock(blockHash, using: view),
              let txHash = try? Data(hexString: update.extrinsicHash)
        else { return }

        switch await view.dispatchOutcome(txHash: txHash, at: block) {
        case .present(true):
            try? await store.recordSuccessDetected(entryId, at: block)
            await propose(.status(.finalizedSuccess), to: entryId)
        case .present(false):
            await propose(.status(.failure), to: entryId)
        case .absent,
             .failedRead:
            // Unreadable outcome: propose nothing and let the pass decide from state.
            break
        }
    }

    func resolveBlock(_ blockHash: String, using view: any CoinageChainViewProtocol) async -> BlockRef? {
        guard let hash = try? Data(hexString: blockHash) else { return nil }
        return await view.blockRef(forHash: hash).value
    }

    func propose(_ verdict: RuleVerdict, to entryId: TransactionId) async {
        do {
            guard let entry = try await store.fetch(id: entryId) else { return }
            try await transaction.apply(verdict, to: entryId, observedStatus: entry.status)
        } catch {
            logger?.error("Status proposal failed for \(entryId): \(error)")
        }
    }

    /// Releases ownership once and triggers a pass, so the entry is picked up immediately
    /// rather than waiting for the next external trigger.
    func release(_ entryId: TransactionId) {
        guard watched.release(entryId) else { return }
        onRelease()
    }
}
