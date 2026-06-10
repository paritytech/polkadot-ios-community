import Foundation
import Keystore_iOS
import Operation_iOS
import Products
import KeyDerivation
import Individuality
import SubstrateSdk
import SubstrateStorageQuery

enum SPAViewFactory {
    @MainActor
    static func createView(
        configuration: SPAConfiguration,
        flowState: SPAFlowState
    ) -> SPAViewProtocol? {
        let dependencyLocator: TruApiDependenciesLocator = RootDependencyLocator.getDependency()
            ?? TruApiDependenciesLocator()
        let allowanceSupport: AllowanceSupport? = dependencyLocator.getDependency()
        let accountManager = ProductsAccountManager(
            entropyManager: RootEntropyManager.shared,
            allowanceSupport: allowanceSupport
        )

        let wireframe = SPAWireframe(flowState: flowState)
        let signingRouter = ProductsSigningRouter()
        let navigationRouter = ProductsNavigationRouter()
        let permissionRouter = ProductPermissionRouter()
        let topUpRequestRouter = TopUpRequestRouter()
        let paymentRequestRouter = PaymentRequestRouter()

        let entropyManager = RootEntropyManager.shared

        let chainRegistry = ChainRegistryFacade.sharedRegistry

        let resourceKeyManager = ProductResourceKeyManager(
            keychain: Keychain(),
            userDefaults: SharedContainerGroup.userDefaults
        )

        let sponsorFactory = HostTransactionSponsorFactory(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            chainRegistry: chainRegistry,
            logger: Logger.shared
        )

        let nativeApiFactory = ProductsNativeApiFactory(
            chainRegistry: chainRegistry,
            usernameStorage: UsernameStorage(),
            localStorage: ProductsLocalStorage(
                productId: configuration.page.host.toDotDomain(),
                settingsManager: SettingsManager.shared
            ),
            nonProductAccountRegistry: NonProductAccountRegistry.main,
            notificationService: UserNotificationService.shared,
            entropyManager: entropyManager,
            dependencyLocator: dependencyLocator,
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            sponsorFactory: sponsorFactory,
            substrateStorageFacade: SubstrateDataStorageFacade.shared
        )

        let nativeApi = nativeApiFactory.makeApi(
            productId: configuration.page.host.toDotDomain(),
            signingRouter: signingRouter,
            navigationRouter: navigationRouter,
            permissionRouter: permissionRouter,
            topUpRequestRouter: topUpRequestRouter,
            paymentRequestRouter: paymentRequestRouter
        )

        let schemeHandlerProxy = SchemeHandlerProxy()

        let scriptsFactory = SPAScriptsFactory(
            containerScriptProvider: BundledContainerScriptProvider()
        )

        let interactor = SPAInteractor(
            nativeApi: nativeApi,
            scriptsFactory: scriptsFactory,
            dotNsResolver: flowState.dotNsResolver,
            schemeHandlerProxy: schemeHandlerProxy,
            configuration: configuration,
            logger: Logger.shared,
            productRepository: ProductRepositoryFactory().createRepository(),
            chatProviderFactory: ChatContactDataProviderFactory()
        )

        let presenter = SPAPresenter(
            interactor: interactor,
            wireframe: wireframe,
            configuration: configuration
        )
        let view = SPAViewController(
            presenter: presenter,
            configuration: configuration,
            schemeHandlerProxy: schemeHandlerProxy,
            logger: Logger.shared
        )

        presenter.view = view
        interactor.presenter = presenter

        signingRouter.setPresentationView(view)
        navigationRouter.setPresentationView(view)
        navigationRouter.setFlowState(flowState)
        permissionRouter.setPresentationView(view)
        topUpRequestRouter.setPresentationView(view)
        paymentRequestRouter.setPresentationView(view)

        if !configuration.isRootScreen {
            view.hidesBottomBarWhenPushed = true
        }

        return view
    }

    @MainActor
    static func createView(
        page: ProductPage,
        flowState: SPAFlowState
    ) -> SPAViewProtocol? {
        let configuration = SPAConfiguration(
            title: nil,
            isRootScreen: false,
            showMoreButton: true,
            page: page
        )

        return createView(configuration: configuration, flowState: flowState)
    }

    @MainActor
    static func createView(
        productHost: ProductHost,
        flowState: SPAFlowState
    ) -> SPAViewProtocol? {
        createView(page: ProductPage(host: productHost), flowState: flowState)
    }

    @MainActor
    static func createView(page: ProductPage) -> SPAViewProtocol? {
        guard let state = SPAFlowState.create() else {
            return nil
        }

        return createView(page: page, flowState: state)
    }

    @MainActor
    static func createView(productHost: ProductHost) -> SPAViewProtocol? {
        createView(page: ProductPage(host: productHost))
    }

    @MainActor
    static func makeCardNavigationController(for spaView: SPAViewProtocol) -> AppNavigationController {
        let navigationController = AppNavigationController(rootViewController: spaView.controller)
        navigationController.barSettings = .transparentSettings
        navigationController.scrollEdgeBarSettings = .defaultSettings
        return navigationController
    }
}
