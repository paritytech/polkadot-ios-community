import Foundation

/// Tracks voucher state during external payment offboarding.
///
/// Follows the same reserve/process/revert pattern as ``TransferContext``:
/// - ``reserve(vouchers:)`` marks vouchers as pending transfer and stores originals for rollback.
/// - ``process(spentVouchers:newVouchers:)`` deletes spent vouchers and saves surplus.
/// - ``revert()`` restores any still-pending vouchers to their original state.
actor ExternalPaymentTransferContext {
    private let voucherService: VoucherServiceProtocol

    /// Vouchers reserved for this payment — kept for revert on failure.
    private var pendingVouchers: [Voucher] = []

    init(voucherService: VoucherServiceProtocol) {
        self.voucherService = voucherService
    }

    /// Saves surplus vouchers as ``Voucher/State-swift.enum/pendingOnboarding``
    /// before extrinsic submission. Tracked by WAL for crash recovery.
    func savePendingOnboarding(vouchers: [Voucher]) async throws {
        guard !vouchers.isEmpty else { return }
        let pending = vouchers.map { $0.withLocalState(.pendingOnboarding) }
        try await voucherService.save(vouchers: pending)
    }

    /// Marks selected vouchers as pending transfer in persistent storage.
    /// Stores the originals so ``revert()`` can restore them if the payment fails.
    func reserve(vouchers: [Voucher]) async throws {
        pendingVouchers = vouchers
        if !vouchers.isEmpty {
            try await voucherService.markPendingTransfer(identifiers: vouchers.map(\.identifier))
        }
    }

    /// Reverts reserved vouchers to their original state after a payment failure.
    func revert() async {
        let toRevert = pendingVouchers
        pendingVouchers = []

        if !toRevert.isEmpty {
            try? await voucherService.save(vouchers: toRevert)
        }
    }

    /// Persists state changes after successful extrinsic submission.
    ///
    /// - Parameters:
    ///   - spentVouchers: Vouchers consumed by unload (to be deleted).
    ///   - newVouchers: Surplus vouchers already saved as `pendingOnboarding`
    ///     (to be marked `available` now that the extrinsic confirmed).
    func process(
        spentVouchers: [Voucher],
        newVouchers: [Voucher] = []
    ) async throws {
        let spentIds = spentVouchers.map(\.identifier)

        pendingVouchers.removeAll { spentIds.contains($0.identifier) }

        do {
            try await voucherService.delete(identifiers: spentIds)
            if !newVouchers.isEmpty {
                try await voucherService.markAvailable(
                    identifiers: newVouchers.map(\.identifier)
                )
            }
        } catch {
            pendingVouchers.append(contentsOf: spentVouchers)
            throw error
        }
    }
}
