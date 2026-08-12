import DesignSystem
import UIKit

internal import SnapKit

public final class DSGlassBackgroundView: UIView {
    public enum Shape: Equatable {
        case capsule
        case rounded(CGFloat)

        @available(iOS, deprecated: 26.0, message: "Use cornerConfiguration instead")
        func cornerRadius(for size: CGSize) -> CGFloat {
            switch self {
            case .capsule: min(size.width, size.height) / 2
            case let .rounded(radius): radius
            }
        }

        @available(iOS 26.0, *)
        var cornerConfiguration: UICornerConfiguration {
            switch self {
            case .capsule:
                .capsule()
            case let .rounded(radius):
                .corners(
                    topLeftRadius: .fixed(radius),
                    topRightRadius: .fixed(radius),
                    bottomLeftRadius: .fixed(radius),
                    bottomRightRadius: .fixed(radius)
                )
            }
        }
    }

    public enum Style: Equatable {
        case regular
        case clear
    }

    private let shape: Shape
    private let effectView: UIVisualEffectView
    private let substrateView = UIView()

    public init(shape: Shape, style: Style = .regular, tint: UIColor? = nil) {
        self.shape = shape

        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: style == .clear ? .clear : .regular)
            effect.tintColor = tint
            effectView = UIVisualEffectView(effect: effect)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }

        super.init(frame: .zero)

        setupHierarchy()
        setupLegacyMaterial()
        applyLayerColors()

        registerForTraitChanges([DSThemeTrait.self]) { (view: DSGlassBackgroundView, _) in
            view.applyLayerColors()
        }
    }

    /// Host for content that should sit inside the glass and adapt to it.
    public var contentView: UIView { effectView.contentView }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        // iOS 26 shapes the glass through cornerConfiguration; the rest is the legacy material.
        guard substrateView.superview != nil else {
            return
        }

        let radius = shape.cornerRadius(for: bounds.size)
        effectView.layer.cornerRadius = radius
        substrateView.layer.cornerRadius = radius
        layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }
}

private extension DSGlassBackgroundView {
    func setupHierarchy() {
        effectView.clipsToBounds = true
        effectView.layer.cornerCurve = .continuous
        addSubview(effectView)
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        if #available(iOS 26.0, *) {
            effectView.cornerConfiguration = shape.cornerConfiguration
        }
    }

    func setupLegacyMaterial() {
        guard #unavailable(iOS 26.0) else {
            return
        }
        substrateView.isUserInteractionEnabled = false
        substrateView.clipsToBounds = true
        substrateView.layer.cornerCurve = .continuous
        substrateView.backgroundColor = .bgSurfaceContainer
        substrateView.alpha = 0.7
        effectView.contentView.insertSubview(substrateView, at: 0)
        substrateView.snp.makeConstraints { make in
            make.edges.equalTo(effectView.contentView)
        }

        layer.borderWidth = 0.8
        layer.cornerCurve = .continuous

        setupShadow()
    }

    func setupShadow() {
        layer.shadowOpacity = 1
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: 8)
    }

    func applyLayerColors() {
        layer.shadowColor = UIColor.shadowSoft.resolvedColor(with: traitCollection).cgColor
        layer.borderColor = UIColor.strokePrimary.resolvedColor(with: traitCollection).cgColor
    }
}

/// A single glass surface with chrome content hosted inside it.
public final class DSGlassContainerView: UIView {
    public let contentView = UIView()

    private let surface: DSGlassBackgroundView

    public init(shape: DSGlassBackgroundView.Shape) {
        surface = DSGlassBackgroundView(shape: shape)

        super.init(frame: .zero)

        addPinnedSubview(surface, to: self)
        addPinnedSubview(contentView, to: surface.contentView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        if hitView === self || hitView === surface || hitView === surface.contentView || hitView === contentView {
            return nil
        }
        return hitView
    }
}

private extension DSGlassContainerView {
    func addPinnedSubview(_ subview: UIView, to container: UIView) {
        container.addSubview(subview)
        subview.snp.makeConstraints { make in
            make.edges.equalTo(container)
        }
    }
}
