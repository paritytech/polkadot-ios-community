import UIKit
import DesignSystem

public extension UILabel {
    /// Bundles a text color + font for one-shot application. Retained for the Products module,
    /// which builds these from Scale encoding/mappings. Prefer setting `font`/`textColor` with
    /// DesignSystem tokens directly elsewhere.
    @available(*, deprecated, message: "Use PolkadotUI.Label.typography + DS color tokens instead")
    struct Style {
        public let textColor: UIColor
        public let font: UIFont

        public init(textColor: UIColor, font: UIFont) {
            self.textColor = textColor
            self.font = font
        }
    }

    func apply(style: Style) {
        textColor = style.textColor
        font = style.font
    }
}
