import Foundation
@preconcurrency import SDKLogger

/// The only writer of `CoinageTxEntry.status`.
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
    private let store: any CoinageTxRepositoryProtocol
    private let watched: CoinageTrackingTxSet
    private let logger: SDKLoggerProtocol?

    public init(store: any CoinageTxRepositoryProtocol, watched: CoinageTrackingTxSet, logger: SDKLoggerProtocol?) {
        self.store = store
        self.watched = watched
        self.logger = logger
    }

    public func apply(
        _ verdict: RuleVerdict,
        to id: CoinageTxId,
        observedStatus: CoinageTxStatus
    ) async throws {
        guard let resolved = Self.resolve(verdict) else { return }

        guard let entry = try await store.fetch(id: id) else {
            logger?.warning("Status proposal for unknown entry \(id)")
            return
        }

        guard entry.status.isLive, entry.status == observedStatus else { return }

        // A submission owns the entry: the status is the watcher's to write and this proposal is a
        // no-op — but `successDetectedAt` is a field write exempt from the watched check, so Rule 0
        // keeps its evidence either way.
        if watched.isWatched(id) {
            if resolved.successDetectedAt.touchesRecord {
                try await store.recordSuccessDetected(id, at: resolved.successDetectedAt.block)
            }
            return
        }

        // Not watched: one atomic compare-and-set is the single guarded writer of both fields.
        try await store.compareAndSetStatus(id, observed: observedStatus, verdict: resolved)
    }
}

private extension StatusUpdateTransaction {
    /// Maps a rule outcome to the ``Verdict`` the store writes — `nil` for the control-flow
    /// outcomes (`searchBodies`, `abort`), which write nothing.
    static func resolve(_ verdict: RuleVerdict) -> Verdict? {
        switch verdict {
        case let .status(status):
            Verdict(status: status, successDetectedAt: .unchanged)
        case let .statusRecordingSuccess(status, block):
            Verdict(status: status, successDetectedAt: .set(block))
        case .clearSuccessAndSetPending:
            Verdict(status: .pending, successDetectedAt: .clear)
        case .searchBodies,
             .abort:
            nil
        }
    }
}
