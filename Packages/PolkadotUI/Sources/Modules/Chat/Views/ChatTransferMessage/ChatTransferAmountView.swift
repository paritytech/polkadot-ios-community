import UIKit
import DesignSystem

final class ChatTransferAmountView: UIView {
    let amountLabel: UILabel = create {
        $0.numberOfLines = 1
    }

    let unitLabel: UILabel = create {
        $0.numberOfLines = 1
    }

    private(set) var typography: TypographyStyle = Constants.typographyLadder[0]

    private let shimmerMaskLayer = CAGradientLayer()
    private var shimmerAnimatedWidth: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(amountLabel)
        addSubview(unitLabel)

        shimmerMaskLayer.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.5).cgColor,
            UIColor.white.cgColor
        ]
        shimmerMaskLayer.locations = [0.4, 0.5, 0.6]
        shimmerMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let amountSize = amountLabel.intrinsicContentSize
        let unitSize = unitLabel.intrinsicContentSize

        return CGSize(
            width: amountSize.width + unitSize.width,
            height: max(amountSize.height, unitSize.height)
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let amountSize = amountLabel.intrinsicContentSize
        let unitSize = unitLabel.intrinsicContentSize
        let amountFont = amountLabel.font ?? UIFont.app(typography)
        let unitFont = unitLabel.font ?? amountFont

        amountLabel.frame = CGRect(origin: .zero, size: amountSize)
        unitLabel.frame = CGRect(
            x: amountSize.width,
            y: amountFont.ascender - unitFont.ascender,
            width: unitSize.width,
            height: unitSize.height
        )

        if layer.mask != nil {
            layoutShimmerMask()
        }
    }

    func bind(currencySymbol: String, amount: String, unit: String, isStruckThrough: Bool = false) {
        let amountText = currencySymbol + amount

        typography = Constants.typographyLadder.first { fits(amountText: amountText, unit: unit, typography: $0) }
            ?? Constants.typographyLadder[Constants.typographyLadder.count - 1]

        let font = UIFont.app(typography)
        amountLabel.font = font
        amountLabel.text = amountText
        if isStruckThrough {
            amountLabel.attributedText = NSAttributedString(
                string: amountText,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
            )
        }
        unitLabel.attributedText = CashLogo.unit(unit, fallback: unitFont(for: font))
        unitLabel.accessibilityLabel = unit

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func setShimmering(_ isActive: Bool) {
        guard isActive else {
            layer.mask = nil
            shimmerMaskLayer.removeAllAnimations()
            shimmerAnimatedWidth = nil
            return
        }
        guard layer.mask == nil else { return }

        layer.mask = shimmerMaskLayer
        layoutShimmerMask()
    }
}

private extension ChatTransferAmountView {
    enum Constants {
        static let typographyLadder: [TypographyStyle] = [.headlineLarge, .headlineSmall, .titleExtraLarge]
        static let maxWidth: CGFloat = 160
        static let shimmerAnimationKey = "shimmer"
        static let shimmerDuration: CFTimeInterval = 1.2
        static let shimmerStartPhase: CGFloat = -0.3
        static let shimmerEndPhase: CGFloat = 1.3
        /// The mask spans three widths so the highlight band clears both edges while sweeping.
        static let shimmerMaskSpan: CGFloat = 3
    }

    func layoutShimmerMask() {
        let width = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMaskLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: width * Constants.shimmerMaskSpan,
            height: bounds.height
        )
        shimmerMaskLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()

        let hasSweep = shimmerMaskLayer.animation(forKey: Constants.shimmerAnimationKey) != nil
        guard !hasSweep || shimmerAnimatedWidth != width else { return }

        shimmerAnimatedWidth = width
        shimmerMaskLayer.removeAnimation(forKey: Constants.shimmerAnimationKey)
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = Constants.shimmerStartPhase * width
        sweep.toValue = Constants.shimmerEndPhase * width
        sweep.duration = Constants.shimmerDuration
        sweep.repeatCount = .infinity
        shimmerMaskLayer.add(sweep, forKey: Constants.shimmerAnimationKey)
    }

    func unitFont(for font: UIFont) -> UIFont {
        UIFont.app(.smallCapsHeadlineMedium).withSize(font.pointSize)
    }

    func fits(amountText: String, unit: String, typography: TypographyStyle) -> Bool {
        let font = UIFont.app(typography)
        let total = width(of: amountText, font: font) + CashLogo.unit(unit, fallback: unitFont(for: font)).size().width

        return total <= Constants.maxWidth
    }

    func width(of text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
