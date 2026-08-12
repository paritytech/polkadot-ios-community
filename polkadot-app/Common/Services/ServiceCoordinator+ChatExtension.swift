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
        audioSessionManager: AudioSessionManaging
    ) -> ChatExtensionsRegistering {
        let productRepositoryFactory = ProductRepositoryFactory()

        let productFileProvider = CompositeProductFileProvider(
            dotNsContentStorage: DotNsContentStorage(),
            chatScriptStorage: FileChatScriptStorage(),
            contentHashCache: ContentHashCache.shared
        )

        let botFactory = ProductBotFactory(
            productFileProvider: productFileProvider,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            usernameStorage: UsernameStorage(),
            notificationService: UserNotificationService.shared,
            runtimeProvider: truapiRuntimeProvider,
            accountManager: accountManager
        )

        let productBotProvider = ProductBotProvider(
            productProvider: productRepositoryFactory.createProvider(),
            botFactory: botFactory
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
