import AsyncExtensions
import BigInt
import Foundation
import SubstrateSdk

/// Public interface for previewing, initiating and monitoring external payments.
public protocol ExternalPaymentServicing {
    /// Two-pass preview: `.spendable` first, widened to `.withConfirmation` only when spendable
    /// funds cannot execute the payment. The returned selection carries the scope it drew on.
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
        destination: AccountId,
        spendScope: SpendScope
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
    case failed(reason: String)
}
