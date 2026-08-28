import UIKit
import DesignSystem

/// Content must be self-sizing.
public final class DSTabBarContentPanelView: UIView {
    public private(set) var isOpen = false

    private let container = UIView()
    private var contentView: (UIView & UIContentView)?
    private var contentReuseIdentifier: String?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        container.clipsToBounds = true
        container.alpha = 0
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setConfiguration(_ configuration: (any HashableContentConfiguration)?) {
        guard let configuration else {
            contentView?.removeFromSuperview()
            contentView = nil
            contentReuseIdentifier = nil
            return
        }

        if let contentView,
           contentReuseIdentifier == configuration.defaultReuseIdentifier {
            contentView.configuration = configuration
            contentView.invalidateIntrinsicContentSize()
            return
        }

        contentView?.removeFromSuperview()

        let newContentView = configuration.makeContentView()
        container.addSubview(newContentView)

        contentView = newContentView
        contentReuseIdentifier = configuration.defaultReuseIdentifier
        setNeedsLayout()
    }

    public func preferredHeight(availableHeight: CGFloat) -> CGFloat {
        guard let contentView, bounds.width > 0 else {
            return DSTabBarMetrics.capsuleHeight
        }

        let measuredSize = contentView.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return DSTabBarPanelLayout.panelHeight(
            contentHeight: measuredSize.height,
            availableHeight: availableHeight
        )
    }

    /// Adds the panel's open/close animations to `animator` so they stay in lockstep with the
    /// container resize the caller drives; applies them immediately when `animator` is nil.
    public func setOpen(_ open: Bool, animator: UIViewPropertyAnimator?) {
        guard open != isOpen else {
            return
        }
        isOpen = open

        let apply = { [self] in
            container.alpha = open ? 1 : 0
        }

        guard let animator else {
            apply()
            return
        }

        animator.addAnimations(apply)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        container.frame = bounds
        contentView?.frame = container.bounds
    }
}
