import UIKit

public struct DSTabBarTrailingSlot: Equatable {
    public let icon: UIImage
    public let accessibilityLabel: String

    public init(
        icon: UIImage,
        accessibilityLabel: String
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
    }
}
