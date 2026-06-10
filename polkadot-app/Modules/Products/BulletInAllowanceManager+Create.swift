import Foundation
import Individuality
import KeyDerivation
import Operation_iOS

extension BulletInAllowanceManager {
    static func create(
        chainRegistry: ChainRegistryProtocol,
        substrateStorageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared
    ) -> BulletInAllowanceManager? {
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

        let infoProvider = BulletInSlotInfoProvider(
            bulletInChainId: AppConfig.Chains.bulletInChain,
            peopleChainId: AppConfig.Chains.usernameChain,
            chainRegistry: chainRegistry,
            keyResolver: keyResolver,
            operationQueue: operationQueue
        )

        let allocator = BulletinSlotAllocator(
            submissionChainId: AppConfig.Chains.usernameChain,
            slotInfoProvider: infoProvider,
            originFactory: originFactory,
            submitter: SlotAssignmentSubmitter(monitorFactory: monitorFactory)
        )

        return BulletInAllowanceManager(
            infoProvider: infoProvider,
            allocator: allocator
        )
    }
}
