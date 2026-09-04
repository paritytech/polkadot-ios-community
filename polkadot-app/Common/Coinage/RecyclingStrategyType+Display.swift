import SwiftUI
import Coinage

/// Presentation for the payment-privacy modes. Copy is hardcoded pending the stage-2 localization pass.
extension RecyclingStrategyType {
    var displayTitle: String {
        switch self {
        case .minPrivacy: "Fastest"
        case .balanced: "Balanced"
        case .maxPrivacy: "Most Private"
        }
    }

    var displayDescription: String {
        switch self {
        case .minPrivacy: "Fastest payments, lower privacy"
        case .balanced: "Stronger privacy, moderate speed"
        case .maxPrivacy: "Maximum privacy, lowest speed"
        }
    }

    var displayIconName: String {
        switch self {
        case .minPrivacy: "bolt.fill"
        case .balanced: "checkmark.shield.fill"
        case .maxPrivacy: "lock.shield.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .minPrivacy: .orange
        case .balanced: .green
        case .maxPrivacy: .purple
        }
    }
}
