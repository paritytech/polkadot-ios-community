import UIKit

public struct DSTabBarItem: Equatable {
    public enum Badge: Equatable {
        case attention

        var color: UIColor {
            switch self {
            case .attention: .bgStatusWarning
            }
        }
    }

    public let icon: UIImage
    public let title: String?
    public var badge: Badge?
    public var accessibilityLabel: String
    public var accessibilityIdentifier: String?

    public init(
        icon: UIImage,
        title: String?,
        badge: Badge? = nil,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}
