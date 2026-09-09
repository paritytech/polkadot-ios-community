import AsyncExtensions
import Foundation

/// Persistence interface for incoming-payment records. Implemented in the main app target to bridge
/// CoreData to the package (mirrors `ExternalPaymentStoring`).
///
/// Status is never stored — it is derived from the CoinageTx durability group. The only mutable bit
/// is ``markProcessed(groupId:)``, flipped once the operation reaches a terminal status; "active"
/// means `processed == false`.
public protocol IncomingPaymentStoring: Sendable {
    /// Persists a new payment. Called once from `accept`, after validation.
    func save(_ payment: IncomingPayment) async throws

    /// The payment with this `groupId` (`"productId:paymentId"`), if any — the idempotency check for
    /// `accept`. Keying by `groupId` scopes the lookup to the product.
    func fetch(groupId: CoinageTxGroupId) async throws -> IncomingPayment?

    /// Every active (`processed == false`) payment — the busy-detection set and the resume set.
    func fetchActivePayments() async throws -> [IncomingPayment]

    /// Flips `processed` to `true` for the record with this `groupId` via a partial mapper (separate
    /// from `save` to avoid fetch-modify-save races — see CLAUDE.md). Idempotent.
    func markProcessed(groupId: CoinageTxGroupId) async throws

    /// Streams a single payment's snapshots by `groupId`: the current value, then every change
    /// (`nil` when absent).
    func observePayment(groupId: CoinageTxGroupId) -> AnyAsyncSequence<IncomingPayment?>

    /// Streams snapshots of the active (`processed == false`) payments: the current set, then a fresh
    /// snapshot on every change. The stream `setup()` subscribes to for resume.
    func observeActivePayments() -> AnyAsyncSequence<[IncomingPayment]>
}
