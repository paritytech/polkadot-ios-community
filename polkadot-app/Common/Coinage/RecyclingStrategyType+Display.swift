import SwiftUI
import DesignSystem
import Coinage

/// Presentation for the payment-privacy modes. Colours map to semantic design-system tokens
/// (warning / success / amethyst) rather than raw values. Copy is hardcoded pending the stage-2
/// localization pass.
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
        case .balanced: "shield.fill"
        case .maxPrivacy: "eye.slash.fill"
        }
    }

    /// The vivid hue: knob icon, gradient stop, marker and selected-label colour.
    var displayAccentColor: Color {
        switch self {
        case .minPrivacy: .fgWarning
        case .balanced: .fgSuccess
        case .maxPrivacy: .avatarFgAmethyst
        }
    }

    /// The muted knob fill, paired with ``displayAccentColor`` for the icon on top.
    var displayFillColor: Color {
        switch self {
        case .minPrivacy: .bgStatusWarning
        case .balanced: .bgStatusSuccess
        case .maxPrivacy: .avatarBgAmethyst
        }
    }
}
