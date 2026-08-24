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
final class ProjectionReconciler: Sendable {
    private let store: any DurabilityStoring
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let logger: SDKLoggerProtocol?

    init(
        store: any DurabilityStoring,
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.coinService = coinService
        self.voucherService = voucherService
        self.logger = logger
    }

    func reconcile() async throws {
        let entries = try await store.fetchAll()
        let claims = try await Claims(entries: entries, handedOff: store.handedOffIdentifiers())

        try await reconcileCoins(claims)
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

// MARK: - Coins

private extension ProjectionReconciler {
    func reconcileCoins(_ claims: Claims) async throws {
        let coins = try await coinService.fetchAllCoins()

        var buckets: [Coin.State: [String]] = [:]
        for coin in coins {
            let key = OwnAsset.coin(coin.derivationIndex).identifier
            guard let target = Self.targetState(for: coin, key: key, claims: claims),
                  target != coin.state
            else { continue }
            buckets[target, default: []].append(coin.identifier)
        }

        for (state, identifiers) in buckets {
            logger?.debug("Reconciler: \(identifiers.count) coins -> \(state)")
            try await apply(state: state, to: identifiers)
        }
    }

    /// The state the entry set implies, or `nil` to leave the row alone.
    static func targetState(
        for coin: Coin,
        key: String,
        claims: Claims
    ) -> Coin.State? {
        // A coin never leaves spent or handed off. Absence of an entry is not evidence that a
        // coin is still ours: entries only exist for operations this install performed, and
        // resurrecting a spent coin is the one error that can double-spend.
        guard coin.state != .spent, coin.state != .handedOff else { return nil }

        if claims.handedOff.contains(key) { return .handedOff }
        // Consumed by an entry that finalized.
        if claims.spentInputs.contains(key) { return .spent }
        // Output of an entry that failed: the key was never minted, so it controls nothing.
        if claims.neverMinted.contains(key) { return .spent }
        if claims.reservedInputs.contains(key) {
            // A coin locked by an in-flight recycling keeps that state so it stays counted as
            // locked value rather than dropping out of the balance entirely.
            return coin.state == .recycling ? nil : .pendingTransfer
        }
        if claims.pendingOutputs.contains(key) { return .pendingMint }
        // A PENDING_SUCCESS output is present at the best head, so it satisfies `selectable`.
        if claims.optimisticOutputs.contains(key) { return .available }
        return .available
    }

    func apply(state: Coin.State, to identifiers: [String]) async throws {
        switch state {
        case .spent: try await coinService.markSpent(coinIds: identifiers)
        case .available: try await coinService.markAvailable(coinIds: identifiers)
        case .recycling: try await coinService.markRecycling(coinIds: identifiers)
        case .pendingTransfer: try await coinService.markPendingTransfer(coinIds: identifiers)
        case .pendingMint: try await coinService.markPendingMint(coinIds: identifiers)
        case .handedOff: try await coinService.markHandedOff(coinIds: identifiers)
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
