import Foundation
import Products
import KeyDerivation
import SubstrateSdk
import Individuality
import SubstrateStorageQuery
import Operation_iOS
import ChainRegistry

extension ServiceCoordinator {
    // swiftlint:disable:next function_parameter_count
    static func createChatExtensionsRegistry(
        accountManager: ProductsAccountManaging,
        truapiRuntimeProvider: TrUAPIHostRuntimeProviding,
        syncStore: DetermineStateSyncStore,
        personDataStore: DetermineStatePersonDataStore,
        syncService: DetermineStateSyncServicing,
        personhoodRegistrationService: PersonhoodRegistrationServicing,
        claimStatusStore: ClaimStatusStore,
        audioSessionManager: AudioSessionManaging,
        spaFlowState: SPAFlowState
    ) -> ChatExtensionsRegistering {
        let productRepositoryFactory = ProductRepositoryFactory()

        let productFileProvider = CompositeProductFileProvider(
            dotNsContentStorage: DotNsContentStorage(),
            chatScriptStorage: FileChatScriptStorage(),
            contentHashCache: ContentHashCache.shared
        )

        let workerFactory = DefaultProductWorkerFactory(
            productResolver: spaFlowState.productResolver,
            dotNsResolver: spaFlowState.dotNsResolver,
            productFileProvider: productFileProvider,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            usernameStorage: UsernameStorage(),
            hostProvider: spaFlowState.hostProvider,
            accountManager: accountManager,
            workerOperations: ProductWorkerServices.shared.operations
        )
        ProductWorkerServices.shared.configure(factory: workerFactory)

        let botFactory = ProductBotFactory(
            productFileProvider: productFileProvider,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            hostProvider: spaFlowState.hostProvider,
            runtimeProvider: truapiRuntimeProvider,
            workerManager: ProductWorkerServices.shared.manager
        )

        let productBotProvider = ProductBotProvider(
            productProvider: productRepositoryFactory.createProvider(),
            botFactory: botFactory,
            dotNsResolver: spaFlowState.dotNsResolver,
            productResolver: spaFlowState.productResolver
        )

        return MainActor.assumeIsolated {
            ChatExtensionsRegistry.createDefault(
                syncStateStore: syncStore,
                personDataStore: personDataStore,
                syncService: syncService,
                personhoodRegistrationService: personhoodRegistrationService,
                claimStatusStore: claimStatusStore,
                productBotProvider: productBotProvider,
                audioSessionManager: audioSessionManager
            )
        }
    }
}
