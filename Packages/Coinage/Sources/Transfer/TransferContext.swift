import Foundation

/// Local projection writes for one transfer.
///
/// The entry set is the source of truth; these writes exist only so balance and selection
/// reflect an operation immediately instead of waiting for the first recovery pass. Anything
/// they get wrong is repaired by `ProjectionReconciler` at the head of the next pass, which is
/// why there is no longer a revert path with its own idea of the correct state.
actor TransferContext {
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let durability: any DurabilityServicing

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        durability: any DurabilityServicing
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
        self.durability = durability
    }

    /// Marks the assets an operation consumes as reserved.
    ///
    /// Coins need no explicit write: a live durability input derives to `.pendingTransfer`. Only
    /// voucher local state is still a materialized projection.
    func reserve(coins _: [Coin], vouchers: [Voucher]) async throws {
        guard !vouchers.isEmpty else { return }
        try await voucherService.markPendingTransfer(identifiers: vouchers.map(\.identifier))
    }

    /// Inserts rows for the coins an entry is expected to mint, so their value is counted
    /// exactly once while the operation is in flight — the inputs are counted nowhere. Their
    /// `.pendingMint` status derives from the pending entry that mints them.
    func insertOutputs(coins: [Coin]) async throws {
        guard !coins.isEmpty else { return }
        try await coinService.save(coins: coins)
    }

    /// Records coins as given to a peer.
    ///
    /// Irreversible by design: the mark is what stops a handed-off coin re-entering an entry,
    /// and what makes its absence on chain readable as a claim rather than as proof the entry
    /// failed.
    func handOff(coins: [Coin]) async throws {
        guard !coins.isEmpty else { return }
        // The handoff mark is the source of truth — `.handedOff` derives from it.
        for coin in coins {
            try await durability.registerHandoff(.coin(coin.derivationIndex))
        }
    }

    /// Asks the engine to recompute local state from the entry set.
    func settle() async {
        durability.startRecoveryPass()
    }
}
