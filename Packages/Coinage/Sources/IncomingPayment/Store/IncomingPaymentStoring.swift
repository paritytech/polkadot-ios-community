import AsyncExtensions
import Foundation

/// Persistence interface for incoming-payment records. Implemented in the main app target to bridge
/// CoreData to the package (mirrors `ExternalPaymentStoring`).
///
/// The record holds no secret material (that lives in `IncomingPaymentSecretStoring`) and no live
/// status. The mutations are ``settle(groupId:outcome:)``, which writes the immutable terminal verdict
/// once, and ``markAcknowledged(groupId:)``, which records that the user has been told; "active"
/// means `outcome == nil`.
public protocol IncomingPaymentStoring: Sendable {
    /// Persists a new payment. Called once from `accept`, after validation.
    func save(_ payment: IncomingPayment) async throws

    /// The payment with this `groupId` (`"top up:productId:paymentId"`), if any — the idempotency
    /// check for `accept`. Keying by `groupId` scopes the lookup to the product.
    func fetch(groupId: CoinageTxGroupId) async throws -> IncomingPayment?

    /// Every active (`outcome == nil`) payment — the busy-detection set and the resume set.
    func fetchActivePayments() async throws -> [IncomingPayment]

    /// Every settled payment the user has not been told about yet — the re-prompt set for `setup()`.
    func fetchUnacknowledgedSettled() async throws -> [IncomingPayment]

    /// Writes the terminal verdict via a partial mapper (separate from `save` to avoid
    /// fetch-modify-save races — see CLAUDE.md). Idempotent; the verdict never changes after this.
    func settle(groupId: CoinageTxGroupId, outcome: IncomingPaymentTerminalOutcome) async throws

    /// Records that the verdict has been surfaced to the user, via a second partial mapper.
    func markAcknowledged(groupId: CoinageTxGroupId) async throws

    /// Streams snapshots of the active (`outcome == nil`) payments — the stream `setup()` subscribes
    /// to for resume.
    func observeActivePayments() -> AnyAsyncSequence<[IncomingPayment]>
}
