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
    private let hostProvider: ProductHostProviding
    private let vrfRepo: BandersnatchManagerRepositoryProtocol

    init(
        productFileProvider: ChatProductFileProviding,
        nativeScriptsFactory: ChatScriptsMaking = ChatNativeRuntimeScriptsFactory(),
        chainRegistry: ChainRegistryProtocol,
        usernameStorage: UsernameStoring,
        hostProvider: ProductHostProviding,
        notificationService: UserNotificationServicing = UserNotificationService.shared,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        runtimeProvider: TrUAPIHostRuntimeProviding,
        accountManager: ProductsAccountManaging,
        vrfRepo: BandersnatchManagerRepositoryProtocol = .shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productFileProvider = productFileProvider
        self.nativeScriptsFactory = nativeScriptsFactory
        self.chainRegistry = chainRegistry
        self.usernameStorage = usernameStorage
        self.hostProvider = hostProvider
        self.notificationService = notificationService
        self.substrateStorageFacade = substrateStorageFacade
        self.entropyManager = entropyManager
        self.settingsManager = settingsManager
        self.runtimeProvider = runtimeProvider
        self.accountManager = accountManager
        self.vrfRepo = vrfRepo
        self.logger = logger
    }

    func create(resolved: ResolvedProduct) -> ProductBot? {
        guard let source = workerSource(for: resolved) else { return nil }

        let product = resolved.product
        let rustRuntimeEnabled = settingsManager.value(for: .truApiRuntimeEnabled)

        if rustRuntimeEnabled {
            do {
                let runtime = try createRustRuntime(product: product, source: source)
                return ProductBot(product: product, runtime: runtime, logger: logger)
            } catch {
                logger.error(
                    "Rust runtime creation failed for \(product.identifier): \(error); falling back to native"
                )
            }
        }

        do {
            let runtime = try createNativeRuntime(product: product, source: source)
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
    /// A worker comes from a published manifest, or from a script installed by hand through debug
    /// settings. Nil means the product ships no chat surface and gets no bot.
    ///
    /// A bot is a chat surface, so a worker that declares `includes.chat: false` gets none — that
    /// is a valid background-only worker, and iOS has nothing else to run it on.
    func workerSource(for resolved: ResolvedProduct) -> ProductWorkerSource? {
        if let worker = resolved.executables.worker {
            guard worker.includesChat else { return nil }

            return ProductWorkerSource(contentId: worker.identifier, entryRelativePath: worker.entrypoint)
        }

        return productFileProvider.manualScriptEntryPath(productId: resolved.id).map {
            ProductWorkerSource(contentId: resolved.id, entryRelativePath: $0)
        }
    }

    func createNativeRuntime(product: Product, source: ProductWorkerSource) throws -> ChatRuntimeProtocol {
        let engineContext = try ChatProductEngineFactory.makeContext(
            source: source,
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

        let sponsorFactory = try HostTransactionSponsorFactory(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            chainRegistry: chainRegistry,
            keyResolver: vrfRepo.keyResolver(),
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
            substrateStorageFacade: substrateStorageFacade,
            hostProvider: hostProvider,
            workerOperations: ProductWorkerServices.shared.operations
        )

        let scriptExecutor = ProductsScriptExecutor(
            productUrl: engineContext.productUrl,
            scriptsFactory: nativeScriptsFactory,
            engineFactory: engineContext.engineFactory,
            logger: logger
        )

        return ChatNativeRuntime(
            productId: product.identifier,
            scriptExecutor: scriptExecutor,
            nativeApiFactory: nativeApiFactory,
            routers: ProductRoutersFacade.chatExtension()
        )
    }

    /// Builds one rust chat runtime (product execution + localhost ws-bridge)
    /// off the shared runtime. The local session lives on the shared runtime;
    /// a transient provider failure only fails this create.
    func createRustRuntime(product: Product, source: ProductWorkerSource) throws -> ChatRuntimeProtocol {
        let runtime = try runtimeProvider.sharedRuntime()

        let rustEnvironment = RustRuntimeEnvironment(
            runtime: runtime,
            chainRegistry: chainRegistry,
            notificationScheduler: ProductNotificationScheduler.shared,
            ipfsFetcher: IpfsFetcher(ipfsBaseURL: AppConfig.KnownIPFS.main),
            hostProvider: hostProvider,
            logger: logger
        )

        let engineContext = try ChatProductEngineFactory.makeContext(
            source: source,
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
