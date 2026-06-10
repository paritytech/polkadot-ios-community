import UIKit
import Keystore_iOS
import Operation_iOS
import UIKitExt

enum MainTabBarViewFactory {
    @MainActor
    static func createView(
        userNotificationService: UserNotificationServicing,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting? = nil,
        deepLinkHandling: DeferredLinkHandling,
    ) -> MainTabBarViewProtocol? {
        guard let serviceCoordinator = ServiceCoordinator.createDefault() else {
            return nil
        }

        let polkadotSignInService = PolkadotSignInService(
            polkadotHandshakeService: serviceCoordinator.polkadotHandshakeService
        )

        let storageFacade = UserDataStorageFacade.shared
        let flowState = createFlowState(
            serviceCoordinator: serviceCoordinator,
            storageFacade: storageFacade,
            userNotificationService: userNotificationService,
            foregroundVisibilityReporter: foregroundVisibilityReporter
        )

        let moduleNavigator = ModuleNavigator()
        let urlHandler = createURLHandler(
            polkadotSignInService: polkadotSignInService,
            storageFacade: storageFacade,
            serviceCoordinator: serviceCoordinator,
            flowState: flowState,
            moduleNavigator: moduleNavigator
        )

        let mnemonicBackupHelper = MnemonicBackupHelper()
        let interactor = MainTabBarInteractor(
            serviceCoordinator: serviceCoordinator,
            userNotificationService: userNotificationService,
            urlHandlingService: urlHandler,
            deferredLinkHandler: deepLinkHandling,
            mnemonicBackupHelper: mnemonicBackupHelper
        )

        let wireframe = MainTabBarWireframe(serviceCoordinator: serviceCoordinator)

        let presenter = MainTabBarPresenter(interactor: interactor, wireframe: wireframe)

        interactor.presenter = presenter
        polkadotSignInService.output = interactor

        let tabFactory = TabFactory(
            serviceCoordinator: serviceCoordinator,
            flowState: flowState,
            foregroundVisibilityReporter: foregroundVisibilityReporter
        )

        let view = MainTabBarViewController(presenter: presenter, viewFactory: tabFactory)

        presenter.view = view
        presenter.configureViews()

        configurePresentationView(view: view, in: serviceCoordinator)

        return view
    }

    private static func createFlowState(
        serviceCoordinator: ServiceCoordinatorProtocol,
        storageFacade: StorageFacadeProtocol,
        userNotificationService: UserNotificationServicing,
        foregroundVisibilityReporter: PushForegroundVisibilityReporting?
    ) -> ChatFlowState {
        let contactsRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(ChatContactMapper())
        )

        let messageDecoder = ChatPushMessageCoder(encryptionManager: ChatEncryptionManager())
        let notificationsCleaner = PushNotificationsCleaner(
            notificationService: userNotificationService,
            contactRepository: AnyDataProviderRepository(contactsRepository),
            messageDecoder: messageDecoder
        )

        return ChatFlowState(
            extensionsRegistry: serviceCoordinator.chatExtensionsRegistry,
            callCoordinator: serviceCoordinator.callCoordinator,
            outboxService: serviceCoordinator.chatCoordinator.outboxService,
            attachmentUploadStateProvider: serviceCoordinator.attachmentUploadService,
            attachmentDownloadStateProvider: serviceCoordinator.attachmentDownloadService,
            foregroundVisibilityReporter: foregroundVisibilityReporter,
            audioSessionManager: serviceCoordinator.audioSessionManager,
            notificationsCleaner: notificationsCleaner,
            coinageService: serviceCoordinator.coinageService
        )
    }

    private static func createURLHandler(
        polkadotSignInService: PolkadotSignInService,
        storageFacade: StorageFacadeProtocol,
        serviceCoordinator: ServiceCoordinatorProtocol,
        flowState: ChatFlowState,
        moduleNavigator: ModuleNavigating
    ) -> URLHandlingService {
        let chatService = ChatOpenService(
            storageFacade: storageFacade,
            moduleNavigator: moduleNavigator,
            remoteContactResolver: RemoteContactOperationFactory()
        )
        let gameOpen = DIM2OpenService(serviceCoordinator: serviceCoordinator)
        let screenOpen = DIM1OpenService()
        let gameChatOpen = GameChatService(flowState: flowState)
        let fiatOnrampRedirect = FiatOnrampRedirectService(
            fiatOnrampTransactionTracking: serviceCoordinator.fiatOnrampTrackingService
        )
        let payDeeplink = PayDeeplinkService(
            coinageService: serviceCoordinator.coinageService,
            moduleNavigator: moduleNavigator
        )
        let productOpen = ProductSPAOpenService(moduleNavigator: moduleNavigator)
        let w3sPayLauncher = W3sPayLauncher(
            coinageService: serviceCoordinator.coinageService,
            moduleNavigator: moduleNavigator,
            logger: Logger.shared
        )
        let w3sPayDeeplink = W3sPayDeeplinkService(
            launcher: w3sPayLauncher,
            logger: Logger.shared
        )

        return URLHandlingService(children: [
            polkadotSignInService,
            chatService,
            screenOpen,
            gameOpen,
            gameChatOpen,
            fiatOnrampRedirect,
            payDeeplink,
            productOpen,
            w3sPayDeeplink
        ])
    }

    @MainActor
    private static func configurePresentationView(
        view: ControllerBackedProtocol,
        in serviceCoordinator: ServiceCoordinatorProtocol,
    ) {
        serviceCoordinator.accountManager.setPresentationView(view)
    }
}
