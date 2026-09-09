import AsyncExtensions
import Foundation
import SubstrateSdk

/// Idempotent, restart-durable inbound top-ups. Instantiated and driven by the ServiceCoordinator.
public protocol IncomingPaymentServicing: Sendable {
    /// Registers a top-up for `(productId, paymentId)` from `descriptor` and returns once
    /// initialization has concluded — the claim is driven by `setup`'s subscription. Throws
    /// `IncomingPaymentError`.
    func accept(
        amount: Balance,
        descriptor: IncomingPaymentSourceDescriptor,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws

    /// Observes a payment's status, scoped to `(productId, paymentId)`. Returns the live derived
    /// stream for an active payment, or the stored terminal verdict for a settled one.
    func subscribeStatus(
        for paymentId: IncomingPaymentId,
        productId: String
    ) async -> AnyAsyncSequence<IncomingPaymentStatus>

    /// Subscribes to active payments and (re)starts their claim tasks. Idempotent across restarts.
    func setup()

    /// Cancels in-flight claim tasks.
    func throttle()
}

/// Supplies the current denomination context for a claim. Implemented by `CoinageService`.
public protocol DenominationContextProviding: Sendable {
    func denominationContext() async throws -> DenominationBreakdownContext
}
