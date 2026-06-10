import Foundation

public enum VoucherPrivacyLevel: Equatable, Sendable {
    /// All vouchers came from recyclers with a full ring size.
    case full
    /// One or more vouchers came from a recycler with an insufficient ring size.
    case degraded
}
