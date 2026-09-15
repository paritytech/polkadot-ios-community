import Coinage
import Foundation
import KeyDerivation
import Keystore_iOS
import FoundationExt
import SubstrateOperation
import ChainRegistry
import BackgroundExecution
import DurableTransactions
import ExtrinsicService
import Individuality

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
        let claimStatusStore = ClaimStatusStore()

        let externalPaymentStore = ExternalPaymentCoreDataStore(
            storageFacade: UserDataStorageFacade.shared
        )

        let incomingPaymentStore = IncomingPaymentCoreDataStore(
            storageFacade: UserDataStorageFacade.shared
        )

        guard let coinageService = createCoinageService(
            databaseFactory: databaseFactory,
            externalPaymentStore: externalPaymentStore,
            incomingPaymentStore: incomingPaymentStore
        ) else {
            return nil
        }

        let transferMonitor = CoinageTransferMonitor(
            coinageService: coinageService,
            storageFacade: UserDataStorageFacade.shared,
            claimStatusStore: claimStatusStore
        )

        let backupSyncService = CoinageBackupSyncService(coinageService: coinageService)

        return CoinageServices(
            coinageService: coinageService,
            transferMonitor: transferMonitor,
            w3sPaymentTracking: createW3sPaymentTracking(coinageService: coinageService),
            backupSyncService: backupSyncService,
            claimStatusStore: claimStatusStore
        )
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
        externalPaymentStore: ExternalPaymentStoring,
        incomingPaymentStore: IncomingPaymentStoring
    ) -> CoinageService? {
        let logger = Logger.shared
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let coinageChainId = AppConfig.Assets.mainAsset.chainId
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        guard let chain = chainRegistry.getChain(for: coinageChainId) else {
            logger.error("Failed to get chain for coinageChainId: \(coinageChainId)")
            return nil
        }

        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let connection = chainRegistry.getConnection(for: coinageChainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: coinageChainId),
            let fullPersonKeyManager = try? vrfRepo.fullPerson(),
            let lightPersonKeyManager = try? vrfRepo.litePerson()
        else {
            logger.error("Failed to get connection/runtime/personhood keys for coinage")
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
        let viewFunctionFetcher = ViewFunctionFetcher(
            executor: ViewFunctionExecutor(
                chainRegistry: chainRegistry,
                operationQueue: operationQueue
            ),
            chainId: coinageChainId
        )
        let unloadTokenResolver = UnloadTokenResolver(
            runtimeCodingService: runtimeProvider,
            viewFunctionFetcher: viewFunctionFetcher,
            consumedTokenChecker: consumedTokenChecker
        )

        let coinageOriginFactory = CoinageOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            chain: chain,
            voucherKeyFactory: voucherKeypairFactory,
            fullPersonKeyManager: fullPersonKeyManager,
            lightPersonKeyManager: lightPersonKeyManager,
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

        // The engine is shared by every durable domain; coinage registers its oracle with it inside
        // `CoinageService.make` and drives its recovery through `CoinageService.setup`.
        let chainViewFactory = PinnedChainViewFactory(
            chainResource: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )
        let durableEngine = createDurableTransactionEngine(chainViewFactory: chainViewFactory)
        let assetLedger = CoinageAssetLedgerCoreData(storageFacade: UserDataStorageFacade.shared)

        let incomingPaymentSecretStore = IncomingPaymentKeychainSecretStore(keychain: Keychain(), logger: logger)
        let incomingPaymentAcknowledger = TopUpAcknowledgementPresenter()

        guard let installation = createInstallationDependency(
            chainRegistry: chainRegistry,
            extrinsicMonitorFacade: extrinsicMonitorFacade,
            logger: logger
        ) else {
            return nil
        }

        return CoinageService.make(
            chainResource: chainRegistry,
            chain: chain,
            instanceId: AppConfig.Coinage.instanceId,
            databaseFactory: databaseFactory,
            originFactory: coinageOriginFactory,
            extrinsicMonitorFactory: monitorFactory,
            durableEngine: durableEngine,
            chainViewFactory: chainViewFactory,
            assetLedger: assetLedger,
            rootEntropyManager: RootEntropyManager.shared,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            externalPaymentStore: externalPaymentStore,
            incomingPaymentStore: incomingPaymentStore,
            incomingPaymentSecretStore: incomingPaymentSecretStore,
            incomingPaymentAcknowledger: incomingPaymentAcknowledger,
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry),
            recyclingStrategySettings: CoinageRecyclingStrategyStore.shared,
            personOriginProvider: coinageOriginFactory.personOriginProvider,
            viewFunctionFetcher: viewFunctionFetcher,
            installation: installation,
            logger: logger
        )
    }

    /// Registration and recovery of installations run against the `AccountDataStore` contract on
    /// Asset Hub, paid in PGAS by the seed's `//datastore` account.
    static func createInstallationDependency(
        chainRegistry: ChainRegistryProtocol,
        extrinsicMonitorFacade: ExtrinsicSubmissionMonitorFacade,
        logger: LoggerProtocol
    ) -> CoinageInstallationDependency? {
        let assetHubChainId = AppConfig.Chains.assethubChain

        guard
            let assetHub = chainRegistry.getChain(for: assetHubChainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: assetHubChainId),
            let operationFactory = try? extrinsicMonitorFacade.createOperationFactory(chain: assetHub),
            let pgasProvisioner = PGASAccountProvisioner.forDataStoreAccount(chainRegistry: chainRegistry)
        else {
            logger.error("Failed to set up installation registration on Asset Hub")
            return nil
        }

        return CoinageInstallationDependency(
            chainId: assetHubChainId,
            runtimeService: runtimeProvider,
            reviveApi: CoinageReviveContractApi(chainId: assetHubChainId, chainRegistry: chainRegistry),
            configProvider: AccountDataStoreConfigProvider(),
            pgasProvisioner: pgasProvisioner,
            feeEstimator: CoinageRegistrationFeeEstimator(operationFactory: operationFactory),
            deepRecoveryCompletedStore: CoinageDeepRecoveryCompletedStore()
        )
    }
}
