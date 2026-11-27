import Foundation

extension AppConfig {
    /// Largest Cash amount a payment may move without device authentication.
    enum ConfirmationLimit {
        static let absolute: Decimal = 50
        static let shareOfTotal: Decimal = 0.5
    }
}
