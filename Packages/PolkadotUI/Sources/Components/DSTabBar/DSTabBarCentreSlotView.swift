import UIKit
import DesignSystem

final class DSTabBarCentreSlotView: UIView {
    var count: Int = 0 {
        didSet { tabsGlyph.count = count }
    }

    var isQRSelected: Bool = false {
        didSet {
            guard isQRSelected != oldValue else { return }
            applyState()
        }
    }

    var isPanelOpen: Bool = false {
        didSet {
            guard isPanelOpen != oldValue else { return }
            applyState()
        }
    }

    var isSPAMounted: Bool = false {
        didSet {
            guard isSPAMounted != oldValue else { return }
            applyState()
        }
    }

    private let divider = UIView()
    private let qrIconView = UIImageView()
    private let tabsGlyph = DSTabBarTabsGlyphView()

    private lazy var qrElement = UIAccessibilityElement(accessibilityContainer: self)
    private lazy var tabsElement = UIAccessibilityElement(accessibilityContainer: self)

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        divider.backgroundColor = UIColor.fgSecondary.withAlphaComponent(Constants.dividerAlpha)
        addSubview(divider)

        qrIconView.contentMode = .scaleAspectFit
        addSubview(qrIconView)
        addSubview(tabsGlyph)

        registerForTraitChanges([DSThemeTrait.self]) { (view: DSTabBarCentreSlotView, _) in
            view.applyState()
            view.tabsGlyph.refreshColorsForTraitChange()
        }

        setupAccessibility()
        applyState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setQRIcon(_ image: UIImage) {
        qrIconView.image = image.withRenderingMode(.alwaysTemplate)
    }

    func setAccessibility(qrLabel: String, tabsLabel: String) {
        qrElement.accessibilityLabel = qrLabel
        tabsElement.accessibilityLabel = tabsLabel
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        divider.frame = CGRect(
            x: (bounds.midX - DSTabBarCentreSlot.dividerWidth / 2).rounded(),
            y: DSTabBarCentreSlot.dividerVerticalInset,
            width: DSTabBarCentreSlot.dividerWidth,
            height: max(0, bounds.height - DSTabBarCentreSlot.dividerVerticalInset * 2)
        )

        qrIconView.frame = DSTabBarCentreSlot.iconFrame(.qr, inSlot: bounds)
        tabsGlyph.frame = DSTabBarCentreSlot.iconFrame(.tabs, inSlot: bounds)

        updateAccessibilityFrames()
    }
}

private extension DSTabBarCentreSlotView {
    enum Constants {
        static let dividerAlpha: CGFloat = 0.4
    }

    func applyState() {
        let tabsActive = DSTabBarCentreSlot.isTabsActive(
            isPanelOpen: isPanelOpen,
            isSPAMounted: isSPAMounted
        )
        let qrActive = DSTabBarCentreSlot.isQRActive(
            isQRSelected: isQRSelected,
            isPanelOpen: isPanelOpen,
            isSPAMounted: isSPAMounted
        )

        qrIconView.tintColor = qrActive ? .fgPrimary : .fgSecondary
        tabsGlyph.glyphColor = tabsActive ? .fgPrimary : .fgSecondary
        qrElement.accessibilityTraits = qrActive ? [.button, .selected] : [.button]
        tabsElement.accessibilityTraits = tabsActive ? [.button, .selected] : [.button]
    }

    func setupAccessibility() {
        accessibilityElements = [qrElement, tabsElement]
    }

    func updateAccessibilityFrames() {
        qrElement.accessibilityFrameInContainerSpace = DSTabBarCentreSlot.halfFrame(.qr, inSlot: bounds)
        tabsElement.accessibilityFrameInContainerSpace = DSTabBarCentreSlot.halfFrame(.tabs, inSlot: bounds)
    }
}
