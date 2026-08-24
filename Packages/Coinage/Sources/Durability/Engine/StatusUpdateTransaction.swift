import Foundation
@preconcurrency import SDKLogger

/// The only writer of `DurabilityEntry.status`.
///
/// Three checks, all as specified:
/// 1. an already-terminal entry is never rewritten, including a `failure` → `finalizedSuccess`
///    raise;
/// 2. a proposal for an entry a submission currently owns is declined;
/// 3. the entry's stored status must still equal the `observedStatus` the verdict was computed
///    from, replacing the spec's "predicates read the status as it stands at the start of the
///    writing transaction".
///
/// Known spec defect: the watcher is required to route its status proposals through this
/// transaction, and the watcher holds the entry for the whole time it is proposing — so every
/// watcher status proposal is a no-op. Correctness is unaffected because statuses land at
/// release and on the next pass; only latency degrades to the pass cadence. `successDetectedAt`
/// is a field write and is deliberately not subject to the watched check, so Rule 0 keeps its
/// evidence either way.
public final class StatusUpdateTransaction: Sendable {
    private let store: any DurabilityStoring
    private let watched: WatchedEntrySet
    private let logger: SDKLoggerProtocol?

    public init(store: any DurabilityStoring, watched: WatchedEntrySet, logger: SDKLoggerProtocol?) {
        self.store = store
        self.watched = watched
        self.logger = logger
    }

    public func apply(
        _ verdict: RuleVerdict,
        to id: TransactionId,
        observedStatus: EntryStatus
    ) async throws {
        guard let target = Self.resolve(verdict) else { return }

        guard let entry = try await store.fetch(id: id) else {
            logger?.warning("Status proposal for unknown entry \(id)")
            return
        }

        guard !entry.status.isTerminal else { return }

        guard entry.status == observedStatus else { return }

        // Field write: not a status change, so it precedes the watched check and lands even
        // while a submission owns the entry.
        if let block = target.successBlock {
            try await store.recordSuccessDetected(id, at: block.value)
        }

        guard !watched.isWatched(id) else { return }

        guard entry.status != target.status else { return }
        try await store.updateStatus(id, to: target.status)
    }
}

private extension StatusUpdateTransaction {
    /// A `successDetectedAt` write, distinguishing "write this block" from "clear it".
    struct SuccessBlockWrite {
        let value: BlockRef?
    }

    struct Target {
        let status: EntryStatus
        let successBlock: SuccessBlockWrite?
    }

    static func resolve(_ verdict: RuleVerdict) -> Target? {
        switch verdict {
        case let .status(status):
            Target(status: status, successBlock: nil)
        case let .statusRecordingSuccess(status, block):
            Target(status: status, successBlock: SuccessBlockWrite(value: block))
        case .clearSuccessAndSetPending:
            Target(status: .pending, successBlock: SuccessBlockWrite(value: nil))
        case .searchBodies,
             .abort:
            nil
        }
    }
}
