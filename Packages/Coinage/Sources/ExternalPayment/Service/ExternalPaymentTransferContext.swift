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

    /// Saves surplus vouchers before extrinsic submission. Their onboarding state is derived from
    /// the durability entry that mints them, so no local flag is written. Tracked for crash recovery.
    func savePendingOnboarding(vouchers: [Voucher]) async throws {
        guard !vouchers.isEmpty else { return }
        try await voucherService.save(vouchers: vouchers)
    }

    /// Records the vouchers reserved for this payment. Their reserved state derives from the live
    /// durability entry consuming them, so no local flag is written; the originals are kept only so
    /// ``revert()`` can restore them if the payment fails.
    func reserve(vouchers: [Voucher]) async throws {
        pendingVouchers = vouchers
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
        newVouchers _: [Voucher] = []
    ) async throws {
        let spentIds = spentVouchers.map(\.identifier)

        pendingVouchers.removeAll { spentIds.contains($0.identifier) }

        do {
            try await voucherService.delete(identifiers: spentIds)
        } catch {
            pendingVouchers.append(contentsOf: spentVouchers)
            throw error
        }
    }
}
