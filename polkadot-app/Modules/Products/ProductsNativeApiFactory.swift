import Foundation
import Coinage
import Products
import StatementStore
import KeyDerivation
import DesignSystem

protocol ProductsNativeApiMaking {
    func makeApi(
        messagingSupport: ProductsNativeApi.MessagingSupport?,
        productId: ProductId,
        signingRouter: SigningRouting,
        navigationRouter: ProductsNavigationRouting,
        permissionRouter: ProductPermissionRouting,
        topUpRequestRouter: TopUpRequestRouting,
        paymentRequestRouter: PaymentRequestRouting
    ) -> any ProductsNativeApiProtocol
}

extension ProductsNativeApiMaking {
    func makeApi(
        productId: ProductId,
        signingRouter: SigningRouting,
        navigationRouter: ProductsNavigationRouting,
        permissionRouter: ProductPermissionRouting,
        topUpRequestRouter: TopUpRequestRouting,
        paymentRequestRouter: PaymentRequestRouting
    ) -> any ProductsNativeApiProtocol {
        makeApi(
            messagingSupport: nil,
            productId: productId,
            signingRouter: signingRouter,
            navigationRouter: navigationRouter,
            permissionRouter: permissionRouter,
            topUpRequestRouter: topUpRequestRouter,
            paymentRequestRouter: paymentRequestRouter
        )
    }
}

final class ProductsNativeApiFactory: ProductsNativeApiMaking {
    private let chainRegistry: ChainRegistryProtocol
    private let usernameStorage: UsernameStoring
    private let localStorage: ProductLocalStorageProtocol
    private let nonProductAccountRegistry: NonProductAccountRegistring
    private let notificationService: UserNotificationServicing
    private let notificationScheduler: ProductNotificationScheduling
    private let entropyManager: RootEntropyManaging
    private let substrateStorageFacade: StorageFacadeProtocol
    private let permissionRepository: ProductPermissionRepositoryProtocol
    private let osPermissionAsker: OSPermissionAsking
    private let paymentsSupport: PaymentsSupport?
    private let accountManager: ProductsAccountManaging
    private let resourceKeyManager: ProductResourceKeyManaging
    private let sponsorFactory: TransactionSponsorMaking
    private let themeManager: ThemeManagerProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        localStorage: ProductLocalStorageProtocol,
        nonProductAccountRegistry: NonProductAccountRegistring,
        notificationService: UserNotificationServicing,
        notificationScheduler: ProductNotificationScheduling = ProductNotificationScheduler.shared,
        entropyManager: RootEntropyManaging,
        dependencyLocator: any DependencyLocator,
        accountManager: ProductsAccountManaging,
        resourceKeyManager: ProductResourceKeyManaging,
        sponsorFactory: TransactionSponsorMaking,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        permissionRepository: ProductPermissionRepositoryProtocol = ProductPermissionRepository(),
        osPermissionAsker: OSPermissionAsking = OSPermissionAsker(),
        themeManager: ThemeManagerProtocol = ThemeManager.shared,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainRegistry = chainRegistry
        self.usernameStorage = usernameStorage
        self.localStorage = localStorage
        self.nonProductAccountRegistry = nonProductAccountRegistry
        self.notificationService = notificationService
        self.notificationScheduler = notificationScheduler
        self.entropyManager = entropyManager
        self.accountManager = accountManager
        self.resourceKeyManager = resourceKeyManager
        self.sponsorFactory = sponsorFactory
        self.substrateStorageFacade = substrateStorageFacade
        self.permissionRepository = permissionRepository
        self.osPermissionAsker = osPermissionAsker
        self.themeManager = themeManager
        self.operationQueue = operationQueue
        self.logger = logger

        paymentsSupport = dependencyLocator.getDependency()
    }

    func makeApi(
        messagingSupport: ProductsNativeApi.MessagingSupport?,
        productId: ProductId,
        signingRouter: SigningRouting,
        navigationRouter: ProductsNavigationRouting,
        permissionRouter: ProductPermissionRouting,
        topUpRequestRouter: TopUpRequestRouting,
        paymentRequestRouter: PaymentRequestRouting
    ) -> any ProductsNativeApiProtocol {
        let permissionGuard = makePermissionGuard(router: permissionRouter)
        let entropyDeriver = ProductRootEntropyDeriver(entropyManager: entropyManager)

        return ProductsNativeApi(
            productId: productId,
            messagingSupport: messagingSupport,
            chainRegistry: chainRegistry,
            usernameStorage: usernameStorage,
            signingRouter: signingRouter,
            navigationRouter: navigationRouter,
            topUpRequestRouter: topUpRequestRouter,
            paymentRequestRouter: paymentRequestRouter,
            localStorage: localStorage,
            nonProductAccountRegistry: nonProductAccountRegistry,
            notificationService: notificationService,
            notificationScheduler: notificationScheduler,
            entropyManager: entropyManager,
            entropyDeriver: entropyDeriver,
            substrateStorageFacade: substrateStorageFacade,
            permissionGuard: permissionGuard,
            paymentsSupport: paymentsSupport,
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            sponsorFactory: sponsorFactory,
            themeManager: themeManager,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

// MARK: - Private

private extension ProductsNativeApiFactory {
    func makePermissionGuard(router: ProductPermissionRouting) -> ProductPermissionGuarding {
        let requester = ProductPermissionRequester(router: router)

        let networkHandler = NetworkAccessPermissionHandler(
            repository: permissionRepository,
            requester: requester
        )
        let remoteHandler = RemotePermissionHandler(
            repository: permissionRepository,
            requester: requester
        )
        let deviceHandler = DeviceCapabilityPermissionHandler(
            repository: permissionRepository,
            requester: requester,
            osAsker: osPermissionAsker
        )
        let accountHandler = AccountAccessPermissionHandler(
            repository: permissionRepository,
            requester: requester
        )

        return ProductPermissionGuard(
            networkHandler: networkHandler,
            remoteHandler: remoteHandler,
            deviceHandler: deviceHandler,
            accountHandler: accountHandler,
            repository: permissionRepository,
            requester: requester
        )
    }
}
