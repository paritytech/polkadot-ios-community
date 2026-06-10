import Foundation
import UIKit
import Keystore_iOS
import Products
import StatementStore
import KeyDerivation

/// Creates ``ProductBot`` instances for a given product,
/// wiring up the script executor with the appropriate storage and engine.
final class ProductBotFactory {
    private let productFileProvider: ChatProductFileProviding
    private let containerScriptProvider: ContainerScriptProviding
    private let nonProductAccountRegistry: NonProductAccountRegistring
    private let notificationService: UserNotificationServicing
    private let chainRegistry: ChainRegistryProtocol
    private let usernameStorage: UsernameStoring
    private let entropyManager: RootEntropyManaging
    private let settingsManager: SettingsManagerProtocol
    private let substrateStorageFacade: StorageFacadeProtocol
    private let logger: LoggerProtocol
    private let accountManager: ProductsAccountManaging

    init(
        productFileProvider: ChatProductFileProviding,
        containerScriptProvider: ContainerScriptProviding = BundledContainerScriptProvider(),
        nonProductAccountRegistry: NonProductAccountRegistring = NonProductAccountRegistry.main,
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        notificationService: UserNotificationServicing = UserNotificationService.shared,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        accountManager: ProductsAccountManaging,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productFileProvider = productFileProvider
        self.containerScriptProvider = containerScriptProvider
        self.nonProductAccountRegistry = nonProductAccountRegistry
        self.chainRegistry = chainRegistry
        self.usernameStorage = usernameStorage
        self.notificationService = notificationService
        self.substrateStorageFacade = substrateStorageFacade
        self.entropyManager = entropyManager
        self.settingsManager = settingsManager
        self.accountManager = accountManager
        self.logger = logger
    }

    func create(product: Product) -> ProductBot? {
        let schemeHandler = ProductScriptSchemeHandler(
            productId: product.identifier,
            entryRelativePath: productFileProvider.productEntryRelativePath(productId: product.identifier),
            productFileProvider: productFileProvider
        )

        guard let baseURL = schemeHandler.getBaseUrl(),
              let productUrl = schemeHandler.getProductUrl() else {
            return nil
        }

        guard let truApiDependencies: TruApiDependenciesLocator = RootDependencyLocator
            .getDependency() else {
            return nil
        }

        let localStorage = ProductsLocalStorage(
            productId: product.identifier,
            settingsManager: settingsManager
        )

        let resourceKeyManager = ProductResourceKeyManager(
            keychain: Keychain(),
            userDefaults: SharedContainerGroup.userDefaults
        )

        let sponsorFactory = HostTransactionSponsorFactory(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            chainRegistry: chainRegistry,
            logger: logger
        )

        let nativeApiFactory = ProductsNativeApiFactory(
            chainRegistry: chainRegistry,
            usernameStorage: usernameStorage,
            localStorage: localStorage,
            nonProductAccountRegistry: nonProductAccountRegistry,
            notificationService: notificationService,
            entropyManager: entropyManager,
            dependencyLocator: truApiDependencies,
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            sponsorFactory: sponsorFactory,
            substrateStorageFacade: substrateStorageFacade
        )

        let scriptExecutor = ProductsScriptExecutor(
            productUrl: productUrl,
            containerScriptProvider: containerScriptProvider,
            engineFactory: { [logger] in
                WKWebViewJSEngine(
                    engineBaseUrl: baseURL,
                    scriptHandlers: [
                        JSEngineLogger(logger: logger)
                    ],
                    hostWindowProvider: { UIWindow.keyWindow },
                    urlSchemeHandlers: [
                        ProductScriptSchemeHandler.scheme: schemeHandler
                    ],
                    logger: logger
                )
            },
            logger: logger
        )

        return ProductBot(
            product: product,
            scriptExecutor: scriptExecutor,
            nativeApiFactory: nativeApiFactory,
            logger: logger
        )
    }
}
