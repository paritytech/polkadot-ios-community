import AssetsManagement
import Foundation
import Individuality
import KeyDerivation
import Products
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery

final class HostTransactionSponsorFactory: TransactionSponsorMaking {
    private let accountManager: ProductsAccountManaging
    private let resourceKeyManager: ProductResourceKeyManaging
    private let chainRegistry: ChainRegistryProtocol
    private let logger: LoggerProtocol

    init(
        accountManager: ProductsAccountManaging,
        resourceKeyManager: ProductResourceKeyManaging,
        chainRegistry: ChainRegistryProtocol,
        logger: LoggerProtocol
    ) {
        self.accountManager = accountManager
        self.resourceKeyManager = resourceKeyManager
        self.chainRegistry = chainRegistry
        self.logger = logger
    }

    func makePreimageSponsor() -> PreimageSubmitSponsoring {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let keyResolver = BandersnatchKeyResolver(
            liteKeyManager: BandersnatchKeyManager.litePerson(),
            fullKeyManager: BandersnatchKeyManager.fullPerson()
        )

        let bulletInInfoProvider = BulletInSlotInfoProvider(
            bulletInChainId: AppConfig.Chains.bulletInChain,
            peopleChainId: AppConfig.Chains.usernameChain,
            chainRegistry: chainRegistry,
            keyResolver: keyResolver,
            operationQueue: operationQueue
        )

        return PreimageSubmitSponsor(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            bulletInInfoProvider: bulletInInfoProvider
        )
    }

    func makePGasSponsor() -> PGasTransactionSponsoring {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        return PGasTransactionSponsor(
            pgasChainAssetId: AppConfig.Assets.pgasAsset,
            assetQueryTypeMaker: AssetQueryTypeFactory(),
            balanceService: BalanceQueryService(
                chainResource: chainRegistry,
                operationQueue: operationQueue
            ),
            accountManager: accountManager,
            chainResource: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )
    }

    func makeStatementStoreSponsor() -> StatementStoreSponsoring {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let keyResolver = BandersnatchKeyResolver(
            liteKeyManager: BandersnatchKeyManager.litePerson(),
            fullKeyManager: BandersnatchKeyManager.fullPerson()
        )

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let slotInfoProvider = StatementStoreSlotInfoProvider(
            chainId: AppConfig.Chains.chatChain,
            chainRegistry: chainRegistry,
            storageRequestFactory: storageRequestFactory,
            keyResolver: keyResolver,
            logger: logger
        )

        return StatementStoreSponsor(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            slotInfoProvider: slotInfoProvider
        )
    }
}
