import Foundation

public enum ExternalPaymentError: Error, Equatable {
    /// A payment with the same `(origin, paymentId)` is already registered.
    case alreadyExists
    case invalidPaymentId
}
