import Foundation
import UIKit
import Keystore_iOS
import Products
import StatementStore
import KeyDerivation
import ChainRegistry
import BulletinChain

/// Creates ``ProductBot`` instances for a given product,
/// wiring up the script executor with the appropriate storage and engine.
final class ProductBotFactory {
    private let productFileProvider: ChatProductFileProviding
    private let nativeScriptsFactory: ChatScriptsMaking
    private let notificationService: UserNotificationServicing
    private let chainRegistry: ChainRegistryProtocol
    private let usernameStorage: UsernameStoring
    private let entropyManager: RootEntropyManaging
    private let settingsManager: SettingsManagerProtocol
    private let substrateStorageFacade: StorageFacadeProtocol
    private let runtimeProvider: TrUAPIHostRuntimeProviding
    private let logger: LoggerProtocol
    private let accountManager: ProductsAccountManaging

    init(
        productFileProvider: ChatProductFileProviding,
        nativeScriptsFactory: ChatScriptsMaking = ChatNativeRuntimeScriptsFactory(),
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        notificationService: UserNotificationServicing = UserNotificationService.shared,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        runtimeProvider: TrUAPIHostRuntimeProviding,
        accountManager: ProductsAccountManaging,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productFileProvider = productFileProvider
        self.nativeScriptsFactory = nativeScriptsFactory
        self.chainRegistry = chainRegistry
        self.usernameStorage = usernameStorage
        self.notificationService = notificationService
        self.substrateStorageFacade = substrateStorageFacade
        self.entropyManager = entropyManager
        self.settingsManager = settingsManager
        self.runtimeProvider = runtimeProvider
        self.accountManager = accountManager
        self.logger = logger
    }

    func create(product: Product) -> ProductBot? {
        let rustRuntimeEnabled = settingsManager.value(for: .truApiRuntimeEnabled)

        if rustRuntimeEnabled {
            do {
                let runtime = try createRustRuntime(product: product)
                return ProductBot(product: product, runtime: runtime, logger: logger)
            } catch {
                logger.error(
                    "Rust runtime creation failed for \(product.identifier): \(error); falling back to native"
                )
            }
        }

        do {
            let runtime = try createNativeRuntime(product: product)
            return ProductBot(product: product, runtime: runtime, logger: logger)
        } catch {
            logger.error("Native runtime creation failed for \(product.identifier): \(error)")
            return nil
        }
    }
}

enum ProductBotFactoryError: Error {
    case dependenciesUnavailable
}

private extension ProductBotFactory {
    func createNativeRuntime(product: Product) throws -> ChatRuntimeProtocol {
        let engineContext = try ChatProductEngineFactory.makeContext(
            productId: product.identifier,
            productFileProvider: productFileProvider,
            logger: logger
        )

        guard let truApiDependencies: TruApiDependenciesLocator = RootDependencyLocator
            .getDependency() else {
            throw ProductBotFactoryError.dependenciesUnavailable
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
            notificationService: notificationService,
            entropyManager: entropyManager,
            dependencyLocator: truApiDependencies,
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            sponsorFactory: sponsorFactory,
            substrateStorageFacade: substrateStorageFacade
        )

        let scriptExecutor = ProductsScriptExecutor(
            productUrl: engineContext.productUrl,
            scriptsFactory: nativeScriptsFactory,
            engineFactory: engineContext.engineFactory,
            logger: logger
        )

        return ChatNativeRuntime(
            productId: product.name,
            scriptExecutor: scriptExecutor,
            nativeApiFactory: nativeApiFactory,
            routers: ProductRoutersFacade.chatExtension()
        )
    }

    /// Builds one rust chat runtime (product execution + localhost ws-bridge)
    /// off the shared runtime. The local session lives on the shared runtime;
    /// a transient provider failure only fails this create.
    func createRustRuntime(product: Product) throws -> ChatRuntimeProtocol {
        let runtime = try runtimeProvider.sharedRuntime()

        let rustEnvironment = RustRuntimeEnvironment(
            runtime: runtime,
            chainRegistry: chainRegistry,
            notificationScheduler: ProductNotificationScheduler.shared,
            ipfsFetcher: IpfsFetcher(ipfsBaseURL: AppConfig.KnownIPFS.main),
            logger: logger
        )

        let engineContext = try ChatProductEngineFactory.makeContext(
            productId: product.identifier,
            productFileProvider: productFileProvider,
            logger: logger
        )

        let routers = ProductRoutersFacade.chatExtension()
        let executionModel = try rustEnvironment.makeChatExecution(
            productId: product.identifier,
            routers: routers
        )

        return ChatRustRuntime(
            productUrl: engineContext.productUrl,
            executionModel: executionModel,
            routers: routers,
            engineFactory: engineContext.engineFactory,
            logger: logger
        )
    }
}
