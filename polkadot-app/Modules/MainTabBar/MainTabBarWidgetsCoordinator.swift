import UIKit
import SnapKit
import PolkadotUI

final class MainTabBarWidgetsCoordinator: UIViewController {
    private let floatingWidgetContainerView = MainTabBarFloatingWidgetStackView()
    private var widgetControllers: [AppWidgetID: AppWidgetContentViewController] = [:]
    private weak var contentSafeAreaAdjustedViewController: UIViewController?
    private var floatingWidgetBottomConstraint: Constraint?
    private var hidesBottomBarForFloatingWidget = false

    private let tabBar: UITabBar
    private let selectedViewControllerProvider: () -> UIViewController?

    init(tabBar: UITabBar, selectedViewControllerProvider: @escaping () -> UIViewController?) {
        self.tabBar = tabBar
        self.selectedViewControllerProvider = selectedViewControllerProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = MainTabBarFloatingWidgetContainerView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        installFloatingWidgetContainer()
        installWidgetsIfNeeded()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateFloatingWidgetBottomConstraint(hidesBottomBar: hidesBottomBarForFloatingWidget)
    }

    func observeNavigationTransitions(in controller: UIViewController) {
        guard let navigationController = controller as? AppNavigationController else {
            return
        }

        navigationController.transitionObserver = self
    }

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        if let controller = widgetControllers[id] {
            controller.update(configuration: configuration)
            updateForSelectedContent()
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

        updateForSelectedContent()
    }

    func selectedViewControllerDidChange() {
        updateForSelectedContent()
    }

    private func updateFloatingWidgetBottomConstraint(hidesBottomBar: Bool = false) {
        hidesBottomBarForFloatingWidget = hidesBottomBar

        if floatingWidgetContainerView.superview != nil {
            view.bringSubviewToFront(floatingWidgetContainerView)
        }

        let bottomOffset = hidesBottomBar ? -view.safeAreaInsets.bottom : -tabBar.bounds.height
        floatingWidgetBottomConstraint?.update(offset: bottomOffset)
    }

    private func installFloatingWidgetContainer() {
        floatingWidgetContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingWidgetContainerView)
        view.bringSubviewToFront(floatingWidgetContainerView)

        floatingWidgetContainerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            floatingWidgetBottomConstraint =
                make.bottom.equalToSuperview().constraint
        }
    }

    private func installWidgetsIfNeeded() {
        widgetControllers.values.forEach(installWidget)
    }

    private func installWidget(_ controller: UIViewController) {
        guard isViewLoaded else {
            return
        }

        controller.loadViewIfNeeded()

        floatingWidgetContainerView.addArrangedSubview(controller.view)

        updateForSelectedContent()
    }

    private func hasAttachedWidget() -> Bool {
        !widgetControllers.isEmpty
    }

    private func floatingWidgetContentHeight() -> CGFloat {
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

    private func animateFloatingWidgetConstraintChange(
        with transitionCoordinator: UIViewControllerTransitionCoordinator?,
        animated: Bool
    ) {
        view.setNeedsLayout()

        guard animated, let transitionCoordinator else {
            view.layoutIfNeeded()
            return
        }

        transitionCoordinator.animate(
            alongsideTransition: { [weak self] _ in
                self?.view.layoutIfNeeded()
            }
        )
    }

    private func selectedContentViewController() -> UIViewController? {
        contentSafeAreaTarget(from: selectedViewControllerProvider())
    }

    private func updateForSelectedContent() {
        updateLayout(for: selectedContentViewController())
    }

    private func updateLayout(for viewController: UIViewController?) {
        updateFloatingWidgetBottomConstraint(
            hidesBottomBar: viewController?.hidesBottomBarWhenPushed ?? tabBar.isHidden
        )
        updateContentSafeAreaInset(for: viewController)
    }

    private func updateContentSafeAreaInset(for viewController: UIViewController?) {
        if contentSafeAreaAdjustedViewController !== viewController {
            contentSafeAreaAdjustedViewController?.additionalSafeAreaInsets.bottom = 0
        }

        guard let viewController else {
            contentSafeAreaAdjustedViewController = nil
            return
        }

        let bottomInset = floatingWidgetContentHeight()
        viewController.additionalSafeAreaInsets.bottom = bottomInset
        contentSafeAreaAdjustedViewController = bottomInset > 0 ? viewController : nil
    }

    private func contentSafeAreaTarget(from viewController: UIViewController?) -> UIViewController? {
        if let navVC = viewController as? UINavigationController {
            navVC.topViewController
        } else {
            viewController
        }
    }
}

extension MainTabBarWidgetsCoordinator: AppNavigationControllerTransitionObserving {
    func appNavigationController(
        _ navigationController: AppNavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        updateLayout(for: viewController)

        if hasAttachedWidget() {
            animateFloatingWidgetConstraintChange(
                with: navigationController.transitionCoordinator,
                animated: animated
            )
        }
    }

    func appNavigationController(
        _: AppNavigationController,
        didShow viewController: UIViewController,
        animated _: Bool
    ) {
        updateLayout(for: viewController)

        guard hasAttachedWidget() else {
            return
        }

        view.layoutIfNeeded()
    }
}

private final class MainTabBarFloatingWidgetContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
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
