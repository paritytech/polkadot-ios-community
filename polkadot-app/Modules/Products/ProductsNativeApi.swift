import Foundation
import Coinage
import Products
import SubstrateSdk
import KeyDerivation
import DesignSystem
import ChainRegistry

/// Concrete implementation of ``ProductsNativeApiProtocol`` that bridges
/// JS bot commands to native wallet, chain registry, and chat capabilities.
final class ProductsNativeApi: ProductsNativeApiProtocol, @unchecked Sendable {
    private(set) weak var bot: (any ChatExtensionBotProtocol)?
    let context: ChatExtensionDiscoverContextProtocol?
    let chainRegistry: ChainRegistryProtocol
    let usernameStorage: UsernameStoring
    let productsRouter: ProductsRouting
    let navigationRouter: ProductsNavigationRouting
    let localStorage: ProductLocalStorageProtocol
    let notificationService: UserNotificationServicing
    let notificationScheduler: ProductNotificationScheduling
    let entropyManager: RootEntropyManaging
    let entropyDeriver: ProductRootEntropyDeriving
    let substrateStorageFacade: StorageFacadeProtocol
    let permissionGuard: ProductPermissionGuarding
    let paymentsSupport: PaymentsSupport?
    let accountManager: ProductsAccountManaging
    let createProofHandler: APCreateProofHandling
    let aliasHandler: APAliasHandling
    let signVrfHandler: APSignVrfHandling
    let resourceKeyManager: ProductResourceKeyManaging
    let sponsorFactory: TransactionSponsorMaking
    let themeManager: ThemeManagerProtocol
    let productId: ProductId

    lazy var preimageSponsor: PreimageSubmitSponsoring = sponsorFactory.makePreimageSponsor()
    lazy var statementStoreSponsor: StatementStoreSponsoring = sponsorFactory.makeStatementStoreSponsor()
    lazy var signingHandler: TransactionSigningHandling = TransactionSigningHandler(
        pgasSponsor: sponsorFactory.makePGasSponsor(),
        chainRegistry: chainRegistry,
        router: productsRouter,
        logger: logger
    )

    lazy var accountResolver: IdentityAccountResolving = IdentityAccountResolver()

    let operationQueue: OperationQueue
    let logger: LoggerProtocol

    init(
        productId: ProductId,
        messagingSupport: MessagingSupport?,
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        productsRouter: ProductsRouting,
        navigationRouter: ProductsNavigationRouting,
        localStorage: ProductLocalStorageProtocol,
        notificationService: UserNotificationServicing,
        notificationScheduler: ProductNotificationScheduling,
        entropyManager: RootEntropyManaging,
        entropyDeriver: ProductRootEntropyDeriving,
        substrateStorageFacade: StorageFacadeProtocol,
        permissionGuard: ProductPermissionGuarding,
        paymentsSupport: PaymentsSupport?,
        accountManager: ProductsAccountManaging,
        createProofHandler: APCreateProofHandling,
        aliasHandler: APAliasHandling,
        signVrfHandler: APSignVrfHandling,
        resourceKeyManager: ProductResourceKeyManaging,
        sponsorFactory: TransactionSponsorMaking,
        themeManager: ThemeManagerProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        bot = messagingSupport?.bot
        context = messagingSupport?.context
        self.productId = productId
        self.chainRegistry = chainRegistry
        self.usernameStorage = usernameStorage
        self.productsRouter = productsRouter
        self.navigationRouter = navigationRouter
        self.localStorage = localStorage
        self.notificationService = notificationService
        self.notificationScheduler = notificationScheduler
        self.entropyManager = entropyManager
        self.entropyDeriver = entropyDeriver
        self.substrateStorageFacade = substrateStorageFacade
        self.permissionGuard = permissionGuard
        self.paymentsSupport = paymentsSupport
        self.accountManager = accountManager
        self.createProofHandler = createProofHandler
        self.aliasHandler = aliasHandler
        self.signVrfHandler = signVrfHandler
        self.resourceKeyManager = resourceKeyManager
        self.sponsorFactory = sponsorFactory
        self.themeManager = themeManager
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension ProductsNativeApi {
    struct MessagingSupport {
        weak var bot: (any ChatExtensionBotProtocol)?
        let context: ChatExtensionDiscoverContextProtocol?
    }
}
