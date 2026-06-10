import Foundation
import Individuality
import KeyDerivation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery

extension SSStoreAllowanceManager {
    static func create(
        chainRegistry: ChainRegistryProtocol,
        userStorageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> SSStoreAllowanceManager? {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let keyResolver = BandersnatchKeyResolver(
            liteKeyManager: BandersnatchKeyManager.litePerson(entropyManager: entropyManager),
            fullKeyManager: BandersnatchKeyManager.fullPerson(entropyManager: entropyManager)
        )

        let originFactory = AsResourcesOriginFactory(
            wallet: SelectedWallet.main,
            keyResolver: keyResolver,
            chainRegistry: chainRegistry
        )

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let extrinsicFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: substrateStorageFacade,
            operationQueue: operationQueue
        )

        guard
            let chatChain = chainRegistry.getChain(for: AppConfig.Chains.chatChain),
            let monitorFactory = try? extrinsicFacade.createMonitorFactory(chain: chatChain)
        else {
            return nil
        }

        let slotInfoProvider = StatementStoreSlotInfoProvider(
            chainId: chatChain.chainId,
            chainRegistry: chainRegistry,
            storageRequestFactory: storageRequestFactory,
            keyResolver: keyResolver,
            logger: Logger.shared
        )

        let allocator = StatementStoreSlotAllocator(
            chainId: chatChain.chainId,
            originFactory: originFactory,
            submitter: SlotAssignmentSubmitter(monitorFactory: monitorFactory),
            slotInfoProvider: slotInfoProvider
        )

        return SSStoreAllowanceManager(
            repository: AllowanceRepositoryFactory(storageFacade: userStorageFacade).createRepository(),
            allocator: allocator,
            slotInfoProvider: slotInfoProvider
        )
    }
}
