import AsyncExtensions
import Foundation
import SubstrateSdk

/// Idempotent, restart-durable inbound top-ups. Instantiated and driven by the ServiceCoordinator.
public protocol IncomingPaymentServicing: Sendable {
    /// Registers a top-up under `paymentId` (the idempotency key) and returns once initialization has
    /// concluded — the claim is driven by `setup`'s subscription. Throws `IncomingPaymentError`.
    func accept(amount: Balance, source: IncomingPaymentSource, paymentId: IncomingPaymentId) async throws

    /// Observes a payment's status. Returns the live derived stream for an active payment, or the
    /// terminal status re-derived from durability for a completed one.
    func subscribeStatus(for paymentId: IncomingPaymentId) async -> AnyAsyncSequence<IncomingPaymentStatus>

    /// Subscribes to active payments and (re)starts their claim tasks. Idempotent across restarts.
    func setup()

    /// Cancels in-flight claim tasks.
    func throttle()
}

/// Supplies the current denomination context for a claim. Implemented by `CoinageService`.
public protocol DenominationContextProviding: Sendable {
    func denominationContext() async throws -> DenominationBreakdownContext
}
