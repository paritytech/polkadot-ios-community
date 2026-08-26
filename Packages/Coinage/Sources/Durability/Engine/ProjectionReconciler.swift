import Foundation
@preconcurrency import SDKLogger

/// Rebuilds local coin and voucher state from the entry set.
///
/// The entry set is the source of truth; `Coin.State` and `Voucher.State` are a materialized
/// projection kept only so the balance service can go on streaming from the CoreData
/// providers. Because entries and their projection live in separate repositories, a crash
/// between the two writes can leave them disagreeing — so this runs at the head of every
/// recovery pass and recomputes the projection from scratch.
///
/// This is the principled replacement for the old orphan sweep, whose "no WAL row therefore
/// never submitted" inference could restore an asset that had in fact been spent.
/// Coin status is derived from the entry graph on read, so only vouchers still carry a
/// materialized projection that this reconciler repairs at the head of each recovery pass.
final class ProjectionReconciler: Sendable {
    private let store: any DurabilityStoring
    private let voucherService: VoucherServiceProtocol
    private let logger: SDKLoggerProtocol?

    init(
        store: any DurabilityStoring,
        voucherService: VoucherServiceProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.voucherService = voucherService
        self.logger = logger
    }

    func reconcile() async throws {
        let entries = try await store.fetchAll()
        let claims = try await Claims(entries: entries, handedOff: store.handedOffIdentifiers())

        try await reconcileVouchers(claims)
    }
}

// MARK: - Claims

private extension ProjectionReconciler {
    /// What the entry set says about each asset, keyed by ``OwnAsset/identifier``.
    struct Claims {
        let handedOff: Set<String>
        let spentInputs: Set<String>
        let neverMinted: Set<String>
        let reservedInputs: Set<String>
        /// Outputs of an entry not yet known to have executed. Not present at any head.
        let pendingOutputs: Set<String>
        /// Outputs of an entry observed to have executed in an unfinalized block. Present at B,
        /// therefore selectable — the optimism `RuleEvaluator` rules 3b/4b exist to withdraw.
        let optimisticOutputs: Set<String>

        init(entries: [DurabilityEntry], handedOff: Set<String>) {
            self.handedOff = handedOff
            spentInputs = entries.inputIdentifiers { $0 == .finalizedSuccess }
            neverMinted = entries.outputIdentifiers { $0 == .failure }
            reservedInputs = entries.inputIdentifiers(where: \.isLive)
            pendingOutputs = entries.outputIdentifiers { $0 == .pending }
            optimisticOutputs = entries.outputIdentifiers { $0 == .pendingSuccess }
        }
    }
}

// MARK: - Vouchers

private extension ProjectionReconciler {
    func reconcileVouchers(_ claims: Claims) async throws {
        let vouchers = try await voucherService.fetchAll()

        var toDelete: [String] = []
        var toPendingTransfer: [String] = []
        var toPendingOnboarding: [String] = []
        var toAvailable: [String] = []

        for voucher in vouchers {
            let key = OwnAsset.recyclerVoucher(voucher.derivationIndex).identifier

            // Unloaded by an entry that finalized, or minted by one that failed: either way
            // there is nothing left to hold locally.
            if claims.spentInputs.contains(key) || claims.neverMinted.contains(key) {
                toDelete.append(voucher.identifier)
            } else if claims.reservedInputs.contains(key) {
                append(voucher, .pendingTransfer, to: &toPendingTransfer)
            } else if claims.pendingOutputs.contains(key) || claims.optimisticOutputs.contains(key) {
                // Vouchers output by any live entry (pending or optimistic) are locked until it
                // resolves, preserving today's behavior where all live outputs are pending.
                append(voucher, .pendingOnboarding, to: &toPendingOnboarding)
            } else {
                append(voucher, .available, to: &toAvailable)
            }
        }

        try await voucherService.delete(identifiers: toDelete)
        try await voucherService.markPendingTransfer(identifiers: toPendingTransfer)
        try await voucherService.markPendingOnboarding(identifiers: toPendingOnboarding)
        try await voucherService.markAvailable(identifiers: toAvailable)
    }

    func append(_ voucher: Voucher, _ state: Voucher.State, to bucket: inout [String]) {
        guard voucher.localState != state else { return }
        bucket.append(voucher.identifier)
    }
}
