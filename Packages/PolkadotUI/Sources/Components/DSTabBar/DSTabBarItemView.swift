import UIKit
import DesignSystem

final class DSTabBarItemView: UIView {
    private let isSelectedAppearance: Bool
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeView = UIView()

    init(isSelectedAppearance: Bool) {
        self.isSelectedAppearance = isSelectedAppearance

        super.init(frame: .zero)

        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ item: DSTabBarItem) {
        iconView.image = item.icon.withRenderingMode(.alwaysTemplate)
        titleLabel.text = item.title
        titleLabel.isHidden = item.title == nil

        badgeView.isHidden = item.badge == nil
        badgeView.backgroundColor = item.badge?.color

        isAccessibilityElement = false
        accessibilityIdentifier = item.accessibilityIdentifier
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let iconSize = DSTabBarMetrics.iconSize
        let iconX = ((bounds.width - iconSize) / 2).rounded()
        let iconY = titleLabel.isHidden
            ? ((bounds.height - iconSize) / 2).rounded()
            : DSTabBarMetrics.itemTopPadding

        iconView.frame = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

        let titleHeight = titleLabel.font.lineHeight.rounded(.up)
        titleLabel.frame = CGRect(
            x: 0,
            y: bounds.height - DSTabBarMetrics.itemBottomPadding - titleHeight,
            width: bounds.width,
            height: titleHeight
        )

        let diameter = DSTabBarMetrics.badgeDiameter
        badgeView.frame = CGRect(
            x: iconView.frame.maxX - diameter + 1.3,
            y: iconView.frame.minY,
            width: diameter,
            height: diameter
        )
        badgeView.layer.cornerRadius = diameter / 2
    }
}

private extension DSTabBarItemView {
    func setupSubviews() {
        isUserInteractionEnabled = false

        let tint: UIColor = isSelectedAppearance ? .fgPrimary : .fgSecondary

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = tint
        addSubview(iconView)

        titleLabel.font = .labelSmallEmphasized
        titleLabel.textAlignment = .center
        titleLabel.textColor = tint
        addSubview(titleLabel)

        badgeView.isHidden = true
        addSubview(badgeView)
    }
}
