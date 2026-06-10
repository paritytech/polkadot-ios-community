import UIKit
import PolkadotUI
import SnapKit
import DesignSystem

final class MainTabBarViewController: UITabBarController {
    let presenter: MainTabBarPresenterProtocol
    let viewFactory: TabFactoryProtocol

    private var controllerIndexByItem: [TabBarItem: Int] = [:]
    private var badgeByItem: [TabBarItem: TabBarBadge] = [:]
    private lazy var widgetsController = MainTabBarWidgetsCoordinator(
        tabBar: tabBar,
        selectedViewControllerProvider: { [weak self] in self?.selectedViewController }
    )

    init(
        presenter: MainTabBarPresenterProtocol,
        viewFactory: TabFactoryProtocol
    ) {
        self.presenter = presenter
        self.viewFactory = viewFactory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        installWidgetsController()
        configureTabBar()

        registerForTraitChanges([DSThemeTrait.self]) { (controller: MainTabBarViewController, _) in
            controller.configureTabBar()
            controller.refreshTabBarItems()
        }

        presenter.setup()
    }

    // MARK: Public methods

    func setTabBar(_ item: TabBarItem) {
        selectTab(at: item.index)
    }
}

// MARK: - Private

private extension MainTabBarViewController {
    func configureTabBar() {
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.fgSecondary,
            .font: UIFont.labelSmall
        ]
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.fgPrimary,
            .font: UIFont.labelSmall
        ]

        let appearance = UITabBarAppearance()
        if #available(iOS 26.0, *) {
            appearance.configureWithDefaultBackground()
        } else {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .bgSurfaceMain
        }
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    func refreshTabBarItems() {
        controllerIndexByItem.forEach { tab, index in
            viewControllers?[index].tabBarItem = viewFactory.tabBarItem(for: tab, badge: badgeByItem[tab])
        }
    }

    func installWidgetsController() {
        addChild(widgetsController)
        view.addSubview(widgetsController.view)

        widgetsController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        widgetsController.didMove(toParent: self)
    }

    func selectTab(at index: Int) {
        selectedIndex = index
        widgetsController.selectedViewControllerDidChange()
    }
}

// MARK: - MainTabBarViewProtocol

extension MainTabBarViewController: MainTabBarViewProtocol {
    func show(tabs: [TabBarItem]) {
        var viewControllers: [UIViewController] = []
        var index = 0
        tabs.forEach { tab in
            guard let viewController = viewFactory.view(for: tab) else {
                return
            }
            widgetsController.observeNavigationTransitions(in: viewController)
            viewControllers.append(viewController)
            controllerIndexByItem[tab] = index
            index += 1
        }

        setViewControllers(viewControllers, animated: false)
        widgetsController.selectedViewControllerDidChange()
    }

    func select(tab: TabBarItem) {
        selectTab(at: tab.index)
    }

    func setBadge(_ badge: TabBarBadge?, for tab: TabBarItem) {
        badgeByItem[tab] = badge
        guard let index = controllerIndexByItem[tab] else {
            return
        }
        viewControllers?[index].tabBarItem = viewFactory.tabBarItem(for: tab, badge: badge)
    }

    func view(for tab: TabBarItem) -> UIViewController? {
        guard let index = controllerIndexByItem[tab] else {
            return nil
        }
        return viewControllers?[index]
    }
}

extension MainTabBarViewController {
    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        view.bringSubviewToFront(widgetsController.view)
        widgetsController.attachWidget(configuration, for: id)
    }

    func detachWidget(for id: AppWidgetID) {
        widgetsController.detachWidget(for: id)
    }
}

extension MainTabBarViewController: UITabBarControllerDelegate {
    func tabBarController(
        _: UITabBarController,
        didSelect _: UIViewController
    ) {
        widgetsController.selectedViewControllerDidChange()
    }
}
