import Foundation
import Individuality
import KeyDerivation
import Operation_iOS
import SubstrateStorageQuery
import SubstrateSdk
import ChainRegistry
import BackgroundExecution

extension PGASAllowanceManager {
    static func create(
        chainRegistry: ChainRegistryProtocol,
        userStorageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> PGASAllowanceManager? {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let keyResolver = BandersnatchKeyResolver(
            liteKeyManager: BandersnatchKeyManager.litePerson(entropyManager: entropyManager),
            fullKeyManager: BandersnatchKeyManager.fullPerson(entropyManager: entropyManager)
        )

        let pgasOriginFactory = PGasOriginFactory(
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
            let ahChain = chainRegistry.getChain(for: AppConfig.Chains.assethubChain),
            let monitorFactory = try? extrinsicFacade.createMonitorFactory(chain: ahChain)
        else {
            return nil
        }

        let chainTimeProvider = ChainTimeProvider(
            chainId: ahChain.chainId,
            chainRegistry: chainRegistry,
            storageRequestFactory: storageRequestFactory
        )

        let slotInfoProvider = PGASSlotInfoProvider(
            chainId: ahChain.chainId,
            peopleChainId: AppConfig.Chains.usernameChain,
            chainRegistry: chainRegistry,
            storageRequestFactory: storageRequestFactory,
            keyResolver: keyResolver,
            chainTimeProvider: chainTimeProvider
        )

        let allocator = PGASSlotAllocator(
            submissionChainId: ahChain.chainId,
            originChainId: AppConfig.Chains.usernameChain,
            originFactory: pgasOriginFactory,
            submitter: SlotAssignmentSubmitter(monitorFactory: monitorFactory),
            slotInfoProvider: slotInfoProvider
        )

        return PGASAllowanceManager(
            repository: AllowanceRepositoryFactory(storageFacade: userStorageFacade).createPGASRepository(),
            allocator: allocator,
            slotInfoProvider: slotInfoProvider,
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry)
        )
    }
}
