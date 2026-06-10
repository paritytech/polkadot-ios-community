import Foundation
import Coinage
import Products
import SubstrateSdk
import KeyDerivation
import DesignSystem

/// Concrete implementation of ``ProductsNativeApiProtocol`` that bridges
/// JS bot commands to native wallet, chain registry, and chat capabilities.
final class ProductsNativeApi: ProductsNativeApiProtocol, @unchecked Sendable {
    private(set) weak var bot: (any ChatExtensionBotProtocol)?
    let context: ChatExtensionDiscoverContextProtocol?
    let chainRegistry: ChainRegistryProtocol
    let usernameStorage: UsernameStoring
    let signingRouter: SigningRouting
    let navigationRouter: ProductsNavigationRouting
    let topUpRequestRouter: TopUpRequestRouting
    let paymentRequestRouter: PaymentRequestRouting
    let localStorage: ProductLocalStorageProtocol
    let nonProductAccountRegistry: NonProductAccountRegistring
    let notificationService: UserNotificationServicing
    let notificationScheduler: ProductNotificationScheduling
    let entropyManager: RootEntropyManaging
    let entropyDeriver: ProductRootEntropyDeriving
    let substrateStorageFacade: StorageFacadeProtocol
    let permissionGuard: ProductPermissionGuarding
    let paymentsSupport: PaymentsSupport?
    let accountManager: ProductsAccountManaging
    let resourceKeyManager: ProductResourceKeyManaging
    let sponsorFactory: TransactionSponsorMaking
    let themeManager: ThemeManagerProtocol
    let productId: ProductId

    lazy var preimageSponsor: PreimageSubmitSponsoring = sponsorFactory.makePreimageSponsor()
    lazy var statementStoreSponsor: StatementStoreSponsoring = sponsorFactory.makeStatementStoreSponsor()
    lazy var signingHandler: TransactionSigningHandling = TransactionSigningHandler(
        pgasSponsor: sponsorFactory.makePGasSponsor(),
        chainRegistry: chainRegistry,
        router: signingRouter,
        logger: logger
    )

    let operationQueue: OperationQueue
    let logger: LoggerProtocol

    init(
        productId: ProductId,
        messagingSupport: MessagingSupport?,
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        signingRouter: SigningRouting,
        navigationRouter: ProductsNavigationRouting,
        topUpRequestRouter: TopUpRequestRouting,
        paymentRequestRouter: PaymentRequestRouting,
        localStorage: ProductLocalStorageProtocol,
        nonProductAccountRegistry: NonProductAccountRegistring,
        notificationService: UserNotificationServicing,
        notificationScheduler: ProductNotificationScheduling,
        entropyManager: RootEntropyManaging,
        entropyDeriver: ProductRootEntropyDeriving,
        substrateStorageFacade: StorageFacadeProtocol,
        permissionGuard: ProductPermissionGuarding,
        paymentsSupport: PaymentsSupport?,
        accountManager: ProductsAccountManaging,
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
        self.signingRouter = signingRouter
        self.navigationRouter = navigationRouter
        self.topUpRequestRouter = topUpRequestRouter
        self.paymentRequestRouter = paymentRequestRouter
        self.localStorage = localStorage
        self.nonProductAccountRegistry = nonProductAccountRegistry
        self.notificationService = notificationService
        self.notificationScheduler = notificationScheduler
        self.entropyManager = entropyManager
        self.entropyDeriver = entropyDeriver
        self.substrateStorageFacade = substrateStorageFacade
        self.permissionGuard = permissionGuard
        self.paymentsSupport = paymentsSupport
        self.accountManager = accountManager
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
