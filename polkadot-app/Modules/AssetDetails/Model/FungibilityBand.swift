#if TESTNET_FEATURE
    import Coinage
    import DesignSystem
    import SwiftUI

    /// How a fungibility score is presented. One definition, so the per-holding bars and the
    /// summary composition can never disagree about what counts as "private".
    enum FungibilityBand: Equatable {
        case high
        case medium
        case low

        init(score: UInt8) {
            switch score {
            case 86...: self = .high
            case 51...: self = .medium
            default: self = .low
            }
        }

        var color: Color {
            switch self {
            case .high: .fgStaticWhite
            case .medium: .fgWarning
            case .low: .fgError
            }
        }

        /// Colour for marks drawn *on* `color` — the provenance chain, dots and fanouts.
        /// A white fill needs dark marks; the saturated fills need light ones.
        var ink: Color {
            switch self {
            case .high: .black
            case .medium,
                 .low: .bgSurfaceMain
            }
        }

        /// Every fill is outlined so the white band stays visible against a light surface.
        static let outline = Color.black
        static let outlineWidth: CGFloat = 1
    }
#endif
