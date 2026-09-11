import Foundation

/// Which funds a spend may draw on. Raw values are persisted on external payment records.
public enum SpendScope: Int, Sendable {
    /// Freely spendable now: `allowUse` coins and usable vouchers.
    case spendable = 0
    /// Adds gaining-privacy funds behind a confirmation — but only when the strategy allows it, so it
    /// can never override `maxPrivacy` (where it equals ``spendable``).
    case withConfirmation = 1
}
