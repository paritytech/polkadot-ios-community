import AsyncExtensions
import Foundation
import SubstrateSdk

/// Idempotent, restart-durable inbound top-ups. Instantiated and driven by the ServiceCoordinator.
public protocol IncomingPaymentServicing: Sendable {
    /// Registers a top-up for `productId` under `paymentId` (the product's idempotency key) and
    /// returns once initialization has concluded — the claim is driven by `setup`'s subscription.
    /// The operation is bound to the product: identity is `(productId, paymentId)`. Throws
    /// `IncomingPaymentError`.
    func accept(
        amount: Balance,
        source: IncomingPaymentSource,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws

    /// Observes a payment's status, scoped to `(productId, paymentId)`. Returns the live derived
    /// stream for an active payment, or the terminal status re-derived from durability for a
    /// completed one.
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
