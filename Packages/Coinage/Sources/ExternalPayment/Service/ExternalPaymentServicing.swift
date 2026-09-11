import AsyncExtensions
import BigInt
import Foundation
import SubstrateSdk

/// Public interface for previewing, initiating and monitoring external payments.
public protocol ExternalPaymentServicing {
    /// Plans over everything spendable on-chain right now; the caller has already obtained the user's
    /// privacy consent, so no scope is involved.
    func previewPayment(
        for amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview

    /// Registers a payment with stage `.plan`. Throws ``ExternalPaymentError/alreadyExists`` for a
    /// known `(origin, paymentId)` and ``ExternalPaymentError/invalidPaymentId`` for an empty id.
    func initiatePayment(
        origin: String,
        paymentId: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws

    /// Unknown `(origin, paymentId)` emits `.failed(reason: "unknown payment")` once, then ends.
    func subscribePaymentStatus(
        origin: String,
        paymentId: String
    ) throws -> AnyAsyncSequence<ExternalPaymentStatus>

    func setup(with context: DenominationBreakdownContext)
    func throttle()
}

public enum ExternalPaymentStatus: Sendable, Equatable {
    case processing
    case completed
    /// Terminal with a shortfall: `settledInPlanks` reached the destination, the rest never will.
    case partiallyCompleted(settledInPlanks: Balance)
    case failed(reason: String)
}
