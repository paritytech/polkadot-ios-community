import UIKit

public final class DSTabBarView: UIView {
    private var itemsStorage: [DSTabBarItem] = []

    public var items: [DSTabBarItem] {
        get { itemsStorage }
        set {
            itemsStorage = newValue
            rebuildItemViews()
        }
    }

    public var selectedIndex: Int = 0 {
        didSet {
            guard selectedIndex != oldValue else {
                return
            }
            updateLens(animated: true)
            rebuildAccessibilityElements()
        }
    }

    public var onSelect: ((_ index: Int, _ isReselection: Bool) -> Void)?

    public var onFoldChangeRequested: ((_ folded: Bool, _ velocityX: CGFloat) -> Void)?

    public var spaTabCount: Int = 0 {
        didSet {
            guard spaTabCount != oldValue else { return }
            centreSlotView.count = spaTabCount
            centreSlotView.isHidden = spaTabCount == 0

            guard (oldValue > 0) != (spaTabCount > 0) else {
                updateLens(animated: false)
                setNeedsLayout()
                return
            }
            animateRowReflow()
        }
    }

    public var isPanelOpen: Bool = false {
        didSet {
            guard isPanelOpen != oldValue else { return }
            centreSlotView.isPanelOpen = isPanelOpen
            updateLens(animated: true)
            rebuildAccessibilityElements()
        }
    }

    public var isSPAMounted: Bool = false {
        didSet {
            guard isSPAMounted != oldValue else { return }
            centreSlotView.isSPAMounted = isSPAMounted
            updateLens(animated: true)
            rebuildAccessibilityElements()
        }
    }

    public var onCentreHalfTapped: ((DSTabBarCentreSlot.Half) -> Void)?

    private let content = UIView()
    private let lens = DSTabBarSelectionLens()
    private let centreSlotView = DSTabBarCentreSlotView()

    private var itemViews: [DSTabBarItemView] = []
    private var selectedItemViews: [DSTabBarItemView] = []

    private var dragState: (startX: CGFloat, currentX: CGFloat, index: Int)?

    public var isFolded: Bool = false

    private var animatesLensOnNextLayout = false

    public static func preferredHeight() -> CGFloat {
        DSTabBarMetrics.capsuleHeight + DSTabBarMetrics.bottomGap
    }

    public static var horizontalMargin: CGFloat { DSTabBarMetrics.horizontalMargin }
    public static var maxWidth: CGFloat { DSTabBarMetrics.maxWidth }
    public static var capsuleHeight: CGFloat { DSTabBarMetrics.capsuleHeight }
    public static var bottomGap: CGFloat { DSTabBarMetrics.bottomGap }
    public static var foldGrabZoneWidth: CGFloat { DSTabBarMetrics.foldGrabZoneWidth }

    /// Distance from the screen's leading edge to the chrome capsule's leading edge.
    public static func horizontalInset(availableWidth: CGFloat) -> CGFloat {
        DSTabBarGeometry.capsuleFrame(availableWidth: availableWidth).minX
    }

    public static func foldedTranslationX(availableWidth: CGFloat) -> CGFloat {
        DSTabBarGeometry.foldedTranslationX(availableWidth: availableWidth)
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        setupHierarchy()
        setupGesture()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setBadge(_ badge: DSTabBarItem.Badge?, at index: Int) {
        guard itemsStorage.indices.contains(index) else {
            return
        }
        itemsStorage[index].badge = badge
        itemViews[index].apply(itemsStorage[index])
        selectedItemViews[index].apply(itemsStorage[index])
    }

    public func setCentreAccessibility(qrLabel: String, tabsLabel: String) {
        centreSlotView.setAccessibility(qrLabel: qrLabel, tabsLabel: tabsLabel)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        content.frame = bounds

        let inset = DSTabBarMetrics.innerInset
        lens.frame = content.bounds.insetBy(dx: inset, dy: inset)

        layoutItemViews()
        updateLens(animated: animatesLensOnNextLayout)
        animatesLensOnNextLayout = false
    }

    override public func hitTest(_ point: CGPoint, with _: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return nil
        }

        return content.frame.contains(point) ? self : nil
    }
}

private extension DSTabBarView {
    var row: DSTabBarRow {
        DSTabBarRow(
            width: DSTabBarGeometry.rowWidth(capsuleWidth: bounds.width),
            itemCount: items.count,
            isCentreExpanded: spaTabCount > 0
        )
    }

    var centreSlotFrame: CGRect? {
        guard let centreIndex = row.centreIndex else {
            return nil
        }
        return DSTabBarCentreSlot.slotFrame(itemFrame: row.itemFrame(at: centreIndex))
    }

    var openCentreSlotFrame: CGRect? {
        spaTabCount > 0 ? centreSlotFrame : nil
    }

    func animateRowReflow() {
        animatesLensOnNextLayout = true
        setNeedsLayout()

        UIView.animate(
            withDuration: DSTabBarMetrics.selectionSpringDuration,
            delay: 0,
            usingSpringWithDamping: DSTabBarMetrics.selectionSpringDamping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: { self.layoutIfNeeded() }
        )
    }

    func setupHierarchy() {
        addSubview(content)
        content.addSubview(lens)
        lens.contentView.addSubview(centreSlotView)
        centreSlotView.isHidden = true
    }

    func setupGesture() {
        let recognizer = DSTabSelectionRecognizer(target: self, action: #selector(handleSelection(_:)))
        addGestureRecognizer(recognizer)
    }

    func setupAccessibility() {
        accessibilityTraits = .tabBar
        isAccessibilityElement = false
    }

    func rebuildItemViews() {
        (itemViews + selectedItemViews).forEach { $0.removeFromSuperview() }

        itemViews = items.map { item in
            let view = DSTabBarItemView(isSelectedAppearance: false)
            view.apply(item)
            lens.contentView.addSubview(view)
            return view
        }
        selectedItemViews = items.map { item in
            let view = DSTabBarItemView(isSelectedAppearance: true)
            view.apply(item)
            lens.selectedContentView.addSubview(view)
            return view
        }

        rebuildAccessibilityElements()
        setNeedsLayout()
    }

    func layoutItemViews() {
        let row = row
        for index in items.indices {
            let frame = row.itemFrame(at: index)
            itemViews[index].frame = frame
            selectedItemViews[index].frame = frame
        }
        rebuildAccessibilityElements()

        guard let centreIndex = row.centreIndex, let slot = centreSlotFrame else {
            return
        }
        centreSlotView.frame = slot
        centreSlotView.setQRIcon(items[centreIndex].icon)
        itemViews[centreIndex].isHidden = spaTabCount > 0
        selectedItemViews[centreIndex].isHidden = spaTabCount > 0
    }

    func pillFrame(forItemAt index: Int) -> CGRect {
        if index == row.centreIndex, let slot = openCentreSlotFrame {
            return slot
        }
        return row.pillFrame(at: index)
    }

    var isCentreLensParked: Bool {
        spaTabCount > 0 && DSTabBarCentreSlot.isTabsActive(
            isPanelOpen: isPanelOpen,
            isSPAMounted: isSPAMounted
        )
    }

    func updateLens(animated: Bool) {
        guard !items.isEmpty, bounds.width > 0 else {
            return
        }

        centreSlotView.isQRSelected = selectedIndex == row.centreIndex

        let resolvedPillFrame: CGRect
        if let dragState {
            var frame = pillFrame(forItemAt: dragState.index)
            frame.origin.x = DSTabBarGeometry.clampedPillOriginX(
                dragState.currentX,
                pillWidth: frame.width,
                rowWidth: row.width
            )
            resolvedPillFrame = frame
        } else if isCentreLensParked, let centreIndex = row.centreIndex {
            resolvedPillFrame = pillFrame(forItemAt: centreIndex)
        } else {
            resolvedPillFrame = pillFrame(forItemAt: selectedIndex)
        }

        lens.update(pillFrame: resolvedPillFrame, isLifted: dragState != nil, animated: animated)
    }

    func drawnPillIndex(currentX: CGFloat, referenceIndex: Int) -> Int {
        let row = row
        let pillWidth = pillFrame(forItemAt: referenceIndex).width
        let drawnOriginX = DSTabBarGeometry.clampedPillOriginX(currentX, pillWidth: pillWidth, rowWidth: row.width)
        return resolvedItemIndex(atX: drawnOriginX + pillWidth / 2)
    }

    @objc func handleSelection(_ recognizer: DSTabSelectionRecognizer) {
        switch recognizer.state {
        case .began:
            guard !isFolded else {
                return
            }
            let locationX = recognizer.location(in: lens).x
            let index = resolvedItemIndex(atX: locationX)
            let pill = pillFrame(forItemAt: index)
            dragState = (startX: pill.minX, currentX: pill.minX, index: index)
            updateLens(animated: true)
        case .changed:
            guard var state = dragState else {
                return
            }
            state.currentX = state.startX + recognizer.translation(in: self).x
            state.index = drawnPillIndex(currentX: state.currentX, referenceIndex: state.index)
            dragState = state
            updateLens(animated: false)
        case .ended,
             .cancelled,
             .failed:
            let dragIndex = dragState?.index
            dragState = nil

            guard recognizer.state == .ended else {
                updateLens(animated: true)
                return
            }
            applyEndedDecision(for: recognizer, dragIndex: dragIndex)
        default:
            break
        }
    }

    func applyEndedDecision(for recognizer: DSTabSelectionRecognizer, dragIndex: Int?) {
        let velocityX = recognizer.velocity(in: self).x
        let decision = DSTabBarFoldDecision.decide(
            velocityX: velocityX,
            translationX: recognizer.translation(in: self).x,
            isFolded: isFolded,
            foldDistance: DSTabBarGeometry.foldedTranslationX(availableWidth: bounds.width)
        )

        switch decision {
        case .select:
            guard let dragIndex else {
                return
            }
            if dragIndex == row.centreIndex, let slot = openCentreSlotFrame {
                let locationX = recognizer.location(in: lens).x
                let half = DSTabBarCentreSlot.half(atX: locationX, inSlot: slot)
                onCentreHalfTapped?(half)

                guard half == .qr else {
                    updateLens(animated: true)
                    return
                }
            }
            commitSelection(at: dragIndex)
        case .fold,
             .unfold:
            updateLens(animated: true)
            onFoldChangeRequested?(decision == .fold, velocityX)
        case .settle:
            updateLens(animated: true)
        }
    }

    func commitSelection(at index: Int) {
        let isReselection = index == selectedIndex
        selectedIndex = index
        onSelect?(index, isReselection)
        if isReselection {
            updateLens(animated: true)
        }
    }

    func rebuildAccessibilityElements() {
        accessibilityElements = items.enumerated().flatMap { index, item -> [Any] in
            if index == row.centreIndex, spaTabCount > 0 {
                return centreSlotView.accessibilityElements ?? []
            }
            return [itemAccessibilityElement(for: item, at: index)]
        }
    }

    func itemAccessibilityElement(for item: DSTabBarItem, at index: Int) -> UIAccessibilityElement {
        let element = UIAccessibilityElement(accessibilityContainer: self)
        element.accessibilityLabel = item.accessibilityLabel
        element.accessibilityIdentifier = item.accessibilityIdentifier
        element.accessibilityTraits = index == selectedIndex && !isCentreLensParked ? [.button, .selected] : [.button]
        element.accessibilityFrameInContainerSpace = lens.convert(row.itemFrame(at: index), to: self)
        return element
    }
}

extension DSTabBarView {
    func resolvedItemIndex(atX xPosition: CGFloat) -> Int {
        if let slot = openCentreSlotFrame,
           let centreIndex = row.centreIndex,
           xPosition >= slot.minX, xPosition <= slot.maxX {
            return centreIndex
        }
        return row.nearestItemIndex(toX: xPosition)
    }
}
