import UIKit
import PolkadotUI
import Products
import UIKitExt

@MainActor
final class MainTabBarWireframe: MainTabBarWireframeProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol
    private let tabFactory: TabFactoryProtocol
    private let moduleNavigator: ModuleNavigating
    private weak var presentedSettings: UINavigationController?
    private weak var presentedTransferRequest: UIViewController?
    /// Strong: once the first route is shown, nothing else keeps the root presenter alive.
    private let rootObserver: RootStateObserving
    /// Injected rather than read from the tab bar's view, which leaves the window under a full-screen modal.
    private weak var windowScene: UIWindowScene?
    private var paymentsSetupNotice: TopNoticeWindow?
    private var isPaymentsSetupNoticeDismissed = false

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        tabFactory: TabFactoryProtocol,
        moduleNavigator: ModuleNavigating,
        windowScene: UIWindowScene?,
        rootObserver: RootStateObserving
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.tabFactory = tabFactory
        self.moduleNavigator = moduleNavigator
        self.windowScene = windowScene
        self.rootObserver = rootObserver
    }

    func showPolkadotSignIn(with url: URL, view: MainTabBarViewProtocol?) {
        guard let signInView = PolkadotSignInViewFactory.createView(
            serviceCoordinator: serviceCoordinator,
            url: url,
            onResult: { [weak self, weak view] result in
                self?.handleSignInResult(result, view: view)
            }
        ) else {
            return
        }
        view?.controller.present(signInView.controller, animated: true)
    }

    func showPaymentsSetupNotice(isVisible: Bool) {
        guard isVisible else {
            paymentsSetupNotice?.hide()
            isPaymentsSetupNoticeDismissed = false
            return
        }
        guard !isPaymentsSetupNoticeDismissed, let windowScene else {
            return
        }

        let notice = paymentsSetupNotice ?? TopNoticeWindow(windowScene: windowScene)
        paymentsSetupNotice = notice
        notice.show(PaymentsSetupNoticeView { [weak self] in
            self?.isPaymentsSetupNoticeDismissed = true
            self?.paymentsSetupNotice?.hide()
        })
    }

    #if FEATURE_INPUT
        func openChat(_ model: ChatOpenModel) {
            moduleNavigator.openChat(model)
        }
    #else
        func showSearchContact(from view: MainTabBarViewProtocol?) {
            guard let search = SearchContactViewFactory.createView(
                onChatFound: { [moduleNavigator] model in
                    moduleNavigator.openChat(model)
                }
            ) else {
                return
            }

            search.controller.modalPresentationStyle = .fullScreen
            search.controller.modalTransitionStyle = .crossDissolve
            view?.controller.present(search.controller, animated: true)
        }
    #endif

    func showConnectionStatus(_ viewModel: ConnectionStatusSheetViewModel, from view: MainTabBarViewProtocol?) {
        let sheet = ConnectionStatusSheetViewFactory.createView(viewModel: viewModel)
        view?.controller.topmostPresented.present(sheet, animated: true)
    }

    func showSettings(from view: MainTabBarViewProtocol?) {
        guard let settings = tabFactory.makeSettingsNavigation() else {
            return
        }
        presentedSettings = settings
        view?.controller.topmostPresented.present(settings, animated: true)
    }

    func leaveReplacedInstallation() {
        rootObserver.didSettleInstallationStatus()
    }

    /// An open sheet follows newer requests itself, so only one is ever shown.
    func showDeviceTransferRequest(_ request: DeviceTransferRequest, from view: MainTabBarViewProtocol?) {
        guard presentedTransferRequest == nil else { return }

        let requestView = DeviceTransferRequestViewFactory.createView(
            request: request,
            listener: serviceCoordinator.deviceTransferRequestListener,
            observer: rootObserver
        )
        presentedTransferRequest = requestView.controller
        view?.controller.topmostPresented.present(requestView.controller, animated: true)
    }
}

private extension MainTabBarWireframe {
    func handleSignInResult(_ result: PolkadotSignInResult, view: MainTabBarViewProtocol?) {
        switch result {
        case let .success(device):
            view?.controller.showToast(
                message: String(localized: .linkedDevicesSignInDeviceConnected),
                type: .success
            )
            showDeviceDetails(device, view: view)
        case let .noFreeSlots(message):
            let controller = NoSlotsAvailableViewFactory.createView(message: message)
            view?.controller.present(controller, animated: true)
        case .failed:
            view?.controller.showToast(
                message: String(localized: .linkedDevicesSignInError),
                type: .error
            )
        }
    }

    func showDeviceDetails(_ device: Chat.LocalDevice, view: MainTabBarViewProtocol?) {
        guard
            let presenter = view?.controller.topmostPresented,
            let linkedDevicesView = LinkedDevicesViewFactory.createView(serviceCoordinator: serviceCoordinator),
            let detailsView = DeviceDetailsViewFactory.createView(
                device: device,
                serviceCoordinator: serviceCoordinator
            )
        else {
            return
        }

        if let settings = presentedSettings, settings === presenter {
            settings.pushViewController(linkedDevicesView.controller, animated: false)
            settings.pushViewController(detailsView.controller, animated: true)
            return
        }

        guard let settings = tabFactory.makeSettingsNavigation() else {
            return
        }
        presentedSettings = settings
        settings.pushViewController(linkedDevicesView.controller, animated: false)
        settings.pushViewController(detailsView.controller, animated: false)
        presenter.present(settings, animated: true)
    }
}
