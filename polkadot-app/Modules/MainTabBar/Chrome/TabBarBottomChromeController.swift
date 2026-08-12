import UIKit
import PolkadotUI
import SnapKit

private struct ScreenOverride {
    weak var screen: UIViewController?
    var value: TabBarFoldOverride
}

final class TabBarBottomChromeController: UIViewController {
    private let glassContainer = DSGlassContainerView(shape: .rounded(32))
    private let barView = DSTabBarView()
    private let floatingWidgetContainerView = MainTabBarFloatingWidgetStackView()
    private let tabsPanelView = DSTabBarTabsPanelView()

    private var widgetControllers: [AppWidgetID: AppWidgetContentViewController] = [:]
    private weak var contentSafeAreaAdjustedViewController: UIViewController?
    private var floatingWidgetBottomConstraint: Constraint?
    private var glassContainerHeightConstraint: Constraint?

    private weak var appliedTabController: UIViewController?
    private weak var appliedContentController: UIViewController?

    private var isTabRoot = true
    private var stackFolds = false
    private weak var navigationScreen: UIViewController?
    private var screenOverrides: [ScreenOverride] = []
    private var pendingFoldVelocity: CGFloat = 0
    private var isFoldInterpolating = false
    private var state: TabBarFoldState = .shown
    private var appliedGlassContainerHeight: CGFloat = 0
    private var foldAnimator: UIViewPropertyAnimator?
    private var panelAnimator: UIViewPropertyAnimator?
    private var foldOffsetWidth: CGFloat?

    var onSelect: ((_ index: Int, _ isReselection: Bool) -> Void)?
    var onCentreHalfTapped: ((DSTabBarCentreSlot.Half) -> Void)?
    var onChipTapped: ((UUID) -> Void)?
    var onChipCloseRequested: ((UUID) -> Void)?

    private var occupiedHeight: CGFloat {
        guard TabBarFoldPolicy.contributesClearance(isTabRoot: isTabRoot) else {
            return view.safeAreaInsets.bottom
        }
        return DSTabBarView.preferredHeight()
    }

    private var contentClearance: CGFloat {
        max(0, occupiedHeight - view.safeAreaInsets.bottom)
    }

    private var availablePanelHeight: CGFloat {
        view.bounds.height
            - view.safeAreaInsets.top
            - DSTabBarView.preferredHeight()
    }

    override func loadView() {
        view = TabBarChromePassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        installGlassContainer()
        installBar()
        installFloatingWidgetContainer()
        installTabsPanel()
        installWidgetsIfNeeded()

        installOutsideTapRecognizer()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateGlassContainerHeight(animator: nil)

        guard view.bounds.width != foldOffsetWidth else {
            return
        }
        foldOffsetWidth = view.bounds.width
        applyFold(barView.isFolded, animated: false, initialVelocity: 0)
    }

    func setItems(_ items: [DSTabBarItem]) {
        barView.items = items
    }

    func setSelectedIndex(_ index: Int) {
        barView.selectedIndex = index
    }

    func setBadge(_ badge: DSTabBarItem.Badge?, at index: Int) {
        barView.setBadge(badge, at: index)
    }

    func setSPATabs(_ chips: [DSTabBarChip], selected: UUID?) {
        barView.spaTabCount = chips.count
        barView.isSPAMounted = selected != nil
        tabsPanelView.setChips(chips, selected: selected)
        barView.setCentreAccessibility(
            qrLabel: String(localized: .Products.productTabsAccessibilityScanner),
            tabsLabel: String(localized: .Products.productTabsAccessibilityOpenApps(chips.count))
        )
        tabsPanelView.closeActionTitle = String(localized: .Common.close)

        let animator = isPanelOpen ? makePanelAnimator() : nil
        updateGlassContainerHeight(animator: animator)
        animator?.startAnimation()

        if chips.isEmpty || availablePanelHeight <= 0 {
            setPanelOpen(false, animated: true)
        }
    }

    func setPanelOpen(_ open: Bool, animated: Bool) {
        let animator = animated ? makePanelAnimator() : nil

        tabsPanelView.setOpen(open, animator: animator)
        barView.isPanelOpen = open
        (viewIfLoaded as? TabBarChromePassthroughView)?.isOutsideTapEnabled = open
        updateGlassContainerHeight(animator: animator)

        animator?.startAnimation()
    }

    var isPanelOpen: Bool { tabsPanelView.isOpen }

    func apply(
        _ context: TabBarChromeContext,
        animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil
    ) {
        isTabRoot = context.isTabRoot
        stackFolds = context.stackFolds
        navigationScreen = context.screen

        applyLayout(context, animatingAlongside: transitionCoordinator)
        refresh()
    }

    func applyLayout(
        _ context: TabBarChromeContext,
        animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil
    ) {
        appliedTabController = context.tabController
        appliedContentController = context.contentController

        updateLayout(animatingAlongside: transitionCoordinator)
    }

    func setFoldProgress(_ progress: CGFloat, targetFolded: Bool) {
        isFoldInterpolating = true

        let foldedOffset = DSTabBarView.foldedTranslationX(availableWidth: view.bounds.width)
        applyFoldOffset(foldedOffset * (targetFolded ? progress : 1 - progress))
    }

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        if let controller = widgetControllers[id] {
            controller.update(configuration: configuration)
            updateLayout()
            return
        }

        let controller = AppWidgetContentViewController(configuration: configuration)
        widgetControllers[id] = controller
        installWidget(controller)
    }

    func detachWidget(for id: AppWidgetID) {
        guard let controller = widgetControllers.removeValue(forKey: id) else {
            return
        }

        floatingWidgetContainerView.removeArrangedSubview(controller.view)
        controller.view.removeFromSuperview()

        updateLayout()
    }
}

// MARK: - Fold state

private extension TabBarBottomChromeController {
    var currentOverride: TabBarFoldOverride {
        guard let navigationScreen else {
            return .none
        }
        return screenOverrides.first { $0.screen === navigationScreen }?.value ?? .none
    }

    func setUserOverride(_ override: TabBarFoldOverride, velocityX: CGFloat) {
        guard !isTabRoot, let navigationScreen else {
            return
        }

        screenOverrides.removeAll { $0.screen == nil || $0.screen === navigationScreen }
        screenOverrides.append(ScreenOverride(screen: navigationScreen, value: override))

        pendingFoldVelocity = velocityX
        refresh()
    }

    func refresh() {
        apply(state: TabBarFoldPolicy.state(
            isTabRoot: isTabRoot,
            stackFolds: stackFolds,
            override: currentOverride
        ))
    }

    func apply(state newState: TabBarFoldState) {
        let foldVelocity = pendingFoldVelocity
        pendingFoldVelocity = 0

        guard newState != state || isFoldInterpolating else {
            return
        }
        isFoldInterpolating = false

        state = newState
        if newState == .folded {
            setPanelOpen(false, animated: false)
        }
        applyFold(newState == .folded, animated: true, initialVelocity: foldVelocity)
    }

    func applyFold(_ folded: Bool, animated: Bool, initialVelocity: CGFloat) {
        barView.isFolded = folded
        foldOffsetWidth = view.bounds.width

        if foldAnimator?.state == .active {
            foldAnimator?.stopAnimation(false)
            foldAnimator?.finishAnimation(at: .current)
        }
        foldAnimator = nil

        let foldedOffset = DSTabBarView.foldedTranslationX(availableWidth: view.bounds.width)
        let offset = folded ? foldedOffset : 0
        let apply = { self.applyFoldOffset(offset) }

        guard animated else {
            apply()
            return
        }

        let distance = abs(foldedOffset)
        let normalized = distance > 0 ? abs(initialVelocity) / distance : 0
        let timing = UISpringTimingParameters(
            dampingRatio: 0.85,
            initialVelocity: CGVector(dx: normalized, dy: 0)
        )
        let animator = UIViewPropertyAnimator(duration: 0.45, timingParameters: timing)
        animator.addAnimations(apply)
        animator.addCompletion { [weak self] _ in
            self?.foldAnimator = nil
        }
        foldAnimator = animator
        animator.startAnimation()
    }

    /// Glass cannot be moved by a transform on a nested view, so the whole container is translated.
    func applyFoldOffset(_ offset: CGFloat) {
        glassContainer.transform = CGAffineTransform(translationX: offset, y: 0)
        updateFoldGrabZone()
    }

    /// The inset container no longer reaches the screen edge, so the folded bar's tap target
    /// lives on the full-bleed chrome view instead.
    func updateFoldGrabZone() {
        guard let passthroughView = viewIfLoaded as? TabBarChromePassthroughView else {
            return
        }

        guard barView.isFolded else {
            passthroughView.foldGrabZone = .zero
            return
        }

        let height = DSTabBarView.capsuleHeight
        passthroughView.foldGrabZone = CGRect(
            x: 0,
            y: view.bounds.height - DSTabBarView.bottomGap - height,
            width: DSTabBarView.foldGrabZoneWidth,
            height: height
        )
    }
}

// MARK: - Layout

private extension TabBarBottomChromeController {
    func installGlassContainer() {
        view.insertSubview(glassContainer, at: 0)
        glassContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualTo(DSTabBarView.maxWidth)
            make.width.equalToSuperview().offset(-DSTabBarView.horizontalMargin * 2).priority(.high)
            make.bottom.equalToSuperview().offset(-DSTabBarView.bottomGap)
            glassContainerHeightConstraint = make.height.equalTo(DSTabBarView.capsuleHeight).constraint
        }
    }

    func installOutsideTapRecognizer() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap))
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
    }

    @objc func handleOutsideTap() {
        guard !barView.isFolded else {
            setUserOverride(.shown, velocityX: 0)
            return
        }
        setPanelOpen(false, animated: true)
    }

    /// One animator drives the panel contents and the container resize so they cannot drift apart.
    func makePanelAnimator() -> UIViewPropertyAnimator {
        if panelAnimator?.state == .active {
            panelAnimator?.stopAnimation(false)
            panelAnimator?.finishAnimation(at: .current)
        }

        let animator = UIViewPropertyAnimator(
            duration: DSTabBarTabsPanelView.openDuration,
            dampingRatio: DSTabBarTabsPanelView.openDampingRatio
        )
        animator.addCompletion { [weak self] _ in
            self?.panelAnimator = nil
        }
        panelAnimator = animator

        return animator
    }

    func updateGlassContainerHeight(animator: UIViewPropertyAnimator?) {
        let containerHeight = isPanelOpen
            ? tabsPanelView.preferredHeight(availableHeight: availablePanelHeight)
            : DSTabBarView.capsuleHeight

        guard containerHeight != appliedGlassContainerHeight else {
            return
        }

        appliedGlassContainerHeight = containerHeight
        glassContainerHeightConstraint?.update(offset: containerHeight)

        animator?.addAnimations { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    func installBar() {
        glassContainer.contentView.addSubview(barView)

        barView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(DSTabBarView.capsuleHeight)
        }

        barView.onSelect = { [weak self] index, isReselection in
            self?.onSelect?(index, isReselection)
        }

        barView.onFoldChangeRequested = { [weak self] folded, velocityX in
            self?.setUserOverride(folded ? .folded : .shown, velocityX: velocityX)
        }

        barView.onCentreHalfTapped = { [weak self] half in
            self?.onCentreHalfTapped?(half)
        }
    }

    func installFloatingWidgetContainer() {
        floatingWidgetContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(floatingWidgetContainerView, belowSubview: glassContainer)

        floatingWidgetContainerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            floatingWidgetBottomConstraint = make.bottom.equalToSuperview().constraint
        }
    }

    func installTabsPanel() {
        glassContainer.contentView.insertSubview(tabsPanelView, belowSubview: barView)

        tabsPanelView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(barView.snp.top)
        }

        tabsPanelView.onChipTapped = { [weak self] id in self?.onChipTapped?(id) }
        tabsPanelView.onChipCloseRequested = { [weak self] id in self?.onChipCloseRequested?(id) }
    }

    func installWidgetsIfNeeded() {
        widgetControllers.values.forEach(installWidget)
    }

    func installWidget(_ controller: UIViewController) {
        guard isViewLoaded else {
            return
        }

        controller.loadViewIfNeeded()
        floatingWidgetContainerView.addArrangedSubview(controller.view)

        updateLayout()
    }

    func hasAttachedWidget() -> Bool {
        !widgetControllers.isEmpty
    }

    func updateLayout(animatingAlongside transitionCoordinator: UIViewControllerTransitionCoordinator? = nil) {
        guard view.window != nil else {
            return
        }

        floatingWidgetBottomConstraint?.update(offset: -occupiedHeight)
        updateContentSafeAreaInset()

        guard hasAttachedWidget() else {
            return
        }

        animateFloatingWidgetConstraintChange(with: transitionCoordinator)
    }

    func updateContentSafeAreaInset() {
        let contentController = appliedContentController

        if contentSafeAreaAdjustedViewController !== contentController {
            contentSafeAreaAdjustedViewController?.additionalSafeAreaInsets.bottom = 0
        }

        let tabController = appliedTabController
        let barInset = contentClearance

        guard let contentController else {
            tabController?.additionalSafeAreaInsets.bottom = barInset
            contentSafeAreaAdjustedViewController = nil
            return
        }

        let widgetInset = floatingWidgetContentHeight()

        if contentController === tabController {
            contentController.additionalSafeAreaInsets.bottom = barInset + widgetInset
        } else {
            tabController?.additionalSafeAreaInsets.bottom = barInset
            contentController.additionalSafeAreaInsets.bottom = widgetInset
        }

        contentSafeAreaAdjustedViewController = widgetInset > 0 ? contentController : nil
    }

    func floatingWidgetContentHeight() -> CGFloat {
        guard hasAttachedWidget() else {
            return 0
        }

        let fittingWidth = max(floatingWidgetContainerView.bounds.width, view.bounds.width)
        let fittingSize = CGSize(
            width: fittingWidth,
            height: UIView.layoutFittingCompressedSize.height
        )
        let measuredSize = floatingWidgetContainerView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        return max(floatingWidgetContainerView.bounds.height, measuredSize.height)
    }

    func animateFloatingWidgetConstraintChange(with transitionCoordinator: UIViewControllerTransitionCoordinator?) {
        view.setNeedsLayout()

        guard let transitionCoordinator else {
            view.layoutIfNeeded()
            return
        }

        transitionCoordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.view.layoutIfNeeded()
            }
        )
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TabBarBottomChromeController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === view
    }
}

private final class TabBarChromePassthroughView: UIView {
    var isOutsideTapEnabled = false
    var foldGrabZone: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        guard hitView === self else {
            return hitView
        }

        if !foldGrabZone.isEmpty, foldGrabZone.contains(point) {
            return self
        }
        return isOutsideTapEnabled ? self : nil
    }
}

private final class MainTabBarFloatingWidgetStackView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .vertical
        alignment = .fill
        distribution = .fill
        spacing = 0
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
