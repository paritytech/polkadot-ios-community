import Foundation

/// Context for persisting transfer state changes.
/// Passed to strategies so they can persist immediately after successful extrinsic submission.
actor TransferContext {
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol

    /// Original coins reserved for this transfer - kept for revert on failure.
    private var pendingCoins: [Coin] = []
    /// Original vouchers reserved for this transfer - kept for revert on failure.
    private var pendingVouchers: [Voucher] = []

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
    }

    /// Marks selected coins and vouchers as pending transfer in persistent storage.
    /// Stores the originals so `revert()` can restore them if the transfer fails.
    func reserve(coins: [Coin], vouchers: [Voucher]) async throws {
        pendingCoins = coins
        pendingVouchers = vouchers
        if !coins.isEmpty {
            try await coinService.markPendingTransfer(coinIds: coins.map(\.identifier))
        }
        if !vouchers.isEmpty {
            try await voucherService.markPendingTransfer(identifiers: vouchers.map(\.identifier))
        }
    }

    /// Reverts reserved coins/vouchers to their original state after a transfer failure.
    func revert() async {
        // Capture and clear before first await to prevent actor re-entrancy issues
        let coinsToRevert = pendingCoins
        let vouchersToRevert = pendingVouchers
        pendingCoins = []
        pendingVouchers = []

        if !coinsToRevert.isEmpty {
            try? await coinService.markAvailable(coinIds: coinsToRevert.map(\.identifier))
        }

        if !vouchersToRevert.isEmpty {
            try? await voucherService.save(vouchers: vouchersToRevert)
        }
    }

    /// Persist state changes after successful extrinsic submission.
    /// - Parameters:
    ///   - spentCoins: Coins consumed by this transfer (to be marked spent)
    ///   - spentVouchers: Vouchers consumed by unload (to be deleted)
    ///   - change: Change coins returned to sender (to be saved)
    func process(
        spentCoins: [Coin] = [],
        spentVouchers: [Voucher] = [],
        change: [Coin] = [],
        destinationCoins: [Coin]
    ) async throws {
        let spentCoinIds = spentCoins.map(\.identifier)
        let spentVoucherIds = spentVouchers.map(\.identifier)
        let destinationCoinIds = destinationCoins.map(\.identifier)

        // Remove only this group's items synchronously before first await (re-entrancy safe).
        // Partial removal (not full clear) so concurrent group calls don't wipe each other's tracking.
        pendingCoins.removeAll { spentCoinIds.contains($0.identifier) }
        pendingVouchers.removeAll { spentVoucherIds.contains($0.identifier) }

        do {
            // save destination and mark as spent
            try await coinService.save(coins: destinationCoins)

            try await coinService.save(coins: change)
            try await coinService.markSpent(coinIds: spentCoinIds + destinationCoinIds)
            try await voucherService.delete(identifiers: spentVoucherIds)
        } catch {
            // Rollback actor state so revert() can still recover these items if a service call fails
            pendingCoins.append(contentsOf: spentCoins)
            pendingVouchers.append(contentsOf: spentVouchers)
            throw error
        }
    }
}
