import UIKit

public struct DSTabBarTrailingSlot: Equatable {
    public let icon: UIImage
    public let accessibilityLabel: String

    /// Overrides the icon's default open/closed tint when the content wants to signal state.
    public let tintColor: UIColor?

    public init(
        icon: UIImage,
        accessibilityLabel: String,
        tintColor: UIColor? = nil
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.tintColor = tintColor
    }
}
