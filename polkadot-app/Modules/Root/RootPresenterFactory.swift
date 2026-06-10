import UIKit
import Keystore_iOS
import Operation_iOS
import JailbreakDetection
import KeyDerivation
import SubstrateSdk

enum RootPresenterFactory: RootPresenterFactoryProtocol {
    static func createPresenter(with window: UIWindow) -> RootPresenterProtocol {
        let foregroundPresentationController = PushForegroundPresentationController()

        let chatRouteHandler = PeerChatPushRouteHandler(
            moduleNavigator: ModuleNavigator(),
            visibilityReporter: foregroundPresentationController
        )

        let chatExtensionRouteHandler = ChatExtensionPushRouteHandler(
            routers: [DIM2ExtensionPushRouter()],
            moduleNavigator: ModuleNavigator(),
            visibilityReporter: foregroundPresentationController
        )

        let deeplinkRouteHandler = DeeplinkPushRouteHandler()

        let pushHandler = PushHandler(
            routeBuilder: PushRouteBuilder(),
            handlers: [chatRouteHandler, chatExtensionRouteHandler, deeplinkRouteHandler]
        )

        let userNotificationService = UserNotificationService.shared
        userNotificationService.setupHandlers(
            pushTapHandler: pushHandler,
            foregroundPresentationDecider: foregroundPresentationController
        )

        let wireframe = RootWireframe(
            window: window,
            userNotificationService: userNotificationService,
            foregroundVisibilityReporter: foregroundPresentationController,
            deepLinkHandling: DeferredLinkHandler.shared
        )

        let migrator = createDatabaseMigrator()

        let jailbreakDetector = JailbreakDetector(
            device: UIDevice.current,
            fileManager: FileManager.default,
            urlOpener: UIApplication.shared,
            processInfo: ProcessInfo.processInfo
        )

        let resolver = SequentialDecisionResolver<RootDestination>(
            preChecks: [RootGate.Jailbreak(detector: jailbreakDetector, logger: Logger.shared)],
            gates: [
                RootGate.Web3SummitStart(),
                RootGate.Web3SummitEnded(),
                RootGate.Theme(),
                RootGate.Wallet(
                    entropyManager: RootEntropyManager.shared,
                    backupHelper: MnemonicBackupHelper()
                ),
                RootGate.Username(usernameStorage: UsernameStorage()),
                RootGate.Web3Summit()
            ],
            fallback: .dashboard
        )

        let makeResolver = { SPAFlowState.create()?.dotNsResolver }
        let chainRegistryClosure = { ChainRegistryFacade.sharedRegistry }

        let browsePrewarmer = ProductContentPrewarmer(
            makeDomain: { AppConfig.DotNs.dotNsBrowse },
            chainRegistryClosure: chainRegistryClosure,
            makeResolver: makeResolver
        )

        let web3SummitPrewarmer = ProductContentPrewarmer(
            makeDomain: { (try? AppConfig.getWeb3Summit())?.dotNsUrl.host() ?? "" },
            chainRegistryClosure: chainRegistryClosure,
            makeResolver: makeResolver
        )

        let interactor = RootInteractor(
            chainRegistryClosure: chainRegistryClosure,
            migrator: migrator,
            logger: Logger.shared,
            resolver: resolver,
            tokenManager: JWTTokenManager.shared,
            browsePrewarmer: browsePrewarmer,
            web3SummitPrewarmer: web3SummitPrewarmer
        )

        let presenter = RootPresenter(
            wireframe: wireframe,
            interactor: interactor,
            viewModelFactory: RootInitViewModelFactory()
        )

        interactor.presenter = presenter

        #if TESTNET_FEATURE
            interactor.appFactoryResetCheckerFactory = AppFactoryResetCheckerFactory(
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                usernameChain: AppConfig.Chains.usernameChain
            )
        #endif

        let initViewController = RootInitViewController()
        presenter.view = initViewController
        window.rootViewController = initViewController

        return presenter
    }

    private static func createDatabaseMigrator() -> Migrating {
        let userStorageMigrator = UserStorageMigrator(
            storeURL: UserStorageParams.storageURL,
            modelDirectory: UserStorageParams.modelDirectory,
            model: UserStorageParams.modelVersion,
            fileManager: FileManager.default
        )

        let substrateStorageMigrator = SubstrateStorageMigrator(
            storeURL: SubstrateStorageParams.storageURL,
            modelDirectory: SubstrateStorageParams.modelDirectory,
            model: SubstrateStorageParams.modelVersion,
            fileManager: FileManager.default
        )

        return SerialMigrator(migrations: [userStorageMigrator, substrateStorageMigrator])
    }
}
