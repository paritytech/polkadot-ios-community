import Coinage
import Foundation
import KeyDerivation
import Keystore_iOS
import FoundationExt
import SubstrateOperation
import ChainRegistry
import BackgroundExecution

extension ServiceCoordinator {
    struct CoinageServices {
        let coinageService: CoinageServicing
        let transferMonitor: CoinageTransferMonitoring
        let w3sPaymentTracking: W3sPaymentTracking
        let backupSyncService: CoinageBackupSyncServicing
        let claimStatusStore: ClaimStatusStore
    }

    static func createCoinageServices() -> CoinageServices? {
        let databaseFactory = CoinageDatabaseDependencyFactory(storageFacade: UserDataStorageFacade.shared)
        let claimPlanStore = ClaimPlanCoreDataStore(storageFacade: UserDataStorageFacade.shared)
        let claimStatusStore = ClaimStatusStore()

        let externalPaymentStore = ExternalPaymentCoreDataStore(
            storageFacade: UserDataStorageFacade.shared
        )

        guard let coinageService = createCoinageService(
            databaseFactory: databaseFactory,
            claimPlanStore: claimPlanStore,
            externalPaymentStore: externalPaymentStore
        ) else {
            return nil
        }

        CoinageRecyclingTaskRegistrator.shared.service = coinageService.recyclingService

        let transferMonitor = CoinageTransferMonitor(
            coinageService: coinageService,
            planStore: claimPlanStore,
            storageFacade: UserDataStorageFacade.shared,
            claimStatusStore: claimStatusStore
        )

        let backupSyncService = CoinageBackupSyncService(
            coinageService: coinageService,
            coinRepository: databaseFactory.makeCoinRepository(),
            voucherRepository: databaseFactory.makeVoucherRepository()
        )

        return CoinageServices(
            coinageService: coinageService,
            transferMonitor: transferMonitor,
            w3sPaymentTracking: createW3sPaymentTracking(coinageService: coinageService),
            backupSyncService: backupSyncService,
            claimStatusStore: claimStatusStore
        )
    }

    static func makeBackgroundRecyclingService() -> (any CoinageRecyclingServicing)? {
        let storageFacade = UserDataStorageFacade.shared
        let databaseFactory = CoinageDatabaseDependencyFactory(storageFacade: storageFacade)
        let claimPlanStore = ClaimPlanCoreDataStore(storageFacade: storageFacade)
        let externalPaymentStore = ExternalPaymentCoreDataStore(storageFacade: storageFacade)

        return createCoinageService(
            databaseFactory: databaseFactory,
            claimPlanStore: claimPlanStore,
            externalPaymentStore: externalPaymentStore
        )?.recyclingService
    }

    private static func createW3sPaymentTracking(coinageService: CoinageServicing) -> W3sPaymentTracking {
        W3sPaymentTrackingService(
            historyStore: W3sPaymentHistoryCoreDataStore(
                storageFacade: UserDataStorageFacade.shared
            ),
            sendVerifier: coinageService.ongoingTransferService,
            blockInfoProvider: BlockInfoProvider(
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                chainId: AppConfig.Assets.mainAsset.chainId
            )
        )
    }
}

// MARK: - CoinageService Creation

private extension ServiceCoordinator {
    static func createCoinageService(
        databaseFactory: DatabaseDependencyFactoring,
        claimPlanStore: ClaimPlanCoreDataStore,
        externalPaymentStore: ExternalPaymentStoring
    ) -> CoinageService? {
        let logger = Logger.shared
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let coinageChainId = AppConfig.Assets.mainAsset.chainId
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        guard let chain = chainRegistry.getChain(for: coinageChainId) else {
            logger.error("Failed to get chain for coinageChainId: \(coinageChainId)")
            return nil
        }

        guard
            let connection = chainRegistry.getConnection(for: coinageChainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: coinageChainId)
        else {
            logger.error("Failed to get connection/runtime for coinage")
            return nil
        }

        let voucherKeypairFactory = VoucherKeypairFactory(
            entropyManager: RootEntropyManager.shared
        )

        let consumedTokenChecker = ConsumedTokenChecker(
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeProvider
        )
        let unloadTokenResolver = UnloadTokenResolver(
            runtimeCodingService: runtimeProvider,
            consumedTokenChecker: consumedTokenChecker
        )

        let coinageOriginFactory = CoinageOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            chain: chain,
            voucherKeyFactory: voucherKeypairFactory,
            fullPersonKeyManager: BandersnatchKeyManager.fullPerson(),
            lightPersonKeyManager: BandersnatchKeyManager.litePerson(),
            unloadTokenResolver: unloadTokenResolver,
            connection: connection,
            runtimeCodingService: runtimeProvider,
            logger: logger
        )

        let extrinsicMonitorFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue
        )
        guard let monitorFactory = try? extrinsicMonitorFacade.createMonitorFactory(
            chain: chain
        ) else {
            logger.error("Failed to create extrinsic monitor factory")
            return nil
        }

        let schedulerFactory = CoinRecycleSchedulerFactory(logger: logger)

        let walStore = TransferWALCoreDataStore(storageFacade: UserDataStorageFacade.shared)

        return CoinageService.make(
            chainResource: chainRegistry,
            chain: chain,
            databaseFactory: databaseFactory,
            originFactory: coinageOriginFactory,
            extrinsicMonitorFactory: monitorFactory,
            rootEntropyManager: RootEntropyManager.shared,
            keystore: Keychain(),
            planStore: claimPlanStore,
            walStore: walStore,
            schedulerFactory: schedulerFactory,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            externalPaymentStore: externalPaymentStore,
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry),
            logger: logger
        )
    }
}
