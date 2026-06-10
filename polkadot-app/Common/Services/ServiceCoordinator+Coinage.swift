import Coinage
import Foundation
import KeyDerivation
import Keystore_iOS
import FoundationExt

extension ServiceCoordinator {
    struct CoinageServices {
        let coinageService: CoinageServicing
        let transferMonitor: CoinageTransferMonitoring
        let backupSyncService: CoinageBackupSyncServicing
        let claimStatusStore: ClaimStatusStore
    }

    static func createCoinageServices() -> CoinageServices? {
        let logger = Logger.shared

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
            backupSyncService: backupSyncService,
            claimStatusStore: claimStatusStore
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
            settingsManager: SettingsManager.shared,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            externalPaymentStore: externalPaymentStore,
            logger: logger
        )
    }
}
