import Coinage
import Foundation

/// Whether an external payment needs the gaining-privacy confirmation before it is registered.
/// Under `minPrivacy` nothing is held back, so there is no privacy to give up; every other preset
/// holds funds back and the sheet is the user's blanket consent to spend them anyway.
enum PaymentPrivacyGate {
    static func requiresPrivacyConfirmation(strategy: RecyclingStrategyType) -> Bool {
        strategy != .minPrivacy
    }
}
