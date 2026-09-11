import Foundation
import ExtrinsicService
import KeyDerivation
import Keystore_iOS
import NovaCrypto
import Operation_iOS
import SDKLogger
import ChainStore
import SubstrateSdk
import SubstrateStorageQuery
import SubstrateOperation
import FoundationExt
import BackgroundExecution
import Individuality

public extension CoinageService {
    /// Creates a CoinageService instance.
    ///
    /// - Parameters:
    ///   - chainResource: Chain resource for RPC connections
    ///   - chain: The chain configuration
    ///   - instanceId: Coinage pallet instance the app operates on (from remote config)
    ///   - databaseFactory: Factory for creating database repositories
    ///   - originFactory: Factory for creating extrinsic origins (app-side implementation)
    ///   - extrinsicMonitorFactory: Factory for extrinsic submission monitoring
    ///   - rootEntropyManager: Manager for root entropy (key derivation)
    ///   - keystore: Keystore for key management
    ///   - logger: Logger for diagnostic output
    ///   - schedulerFactory: Coin recycling background task scheduler
    /// - Returns: A configured CoinageServicing instance
    // swiftlint:disable:next function_body_length
    static func make(
        chainResource: ChainResourceProtocol,
        chain: ChainProtocol,
        instanceId: CoinageInstanceId,
        databaseFactory: DatabaseDependencyFactoring,
        originFactory: OriginCreating,
        extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        extrinsicOperationFactory: any ExtrinsicOperationFactoryProtocol,
        extrinsicSubmitter: any ExtrinsicSubmitting,
        rootEntropyManager: RootEntropyManaging,
        keystore: KeystoreProtocol,
        txStore: any CoinageTxRepositoryProtocol,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        externalPaymentStore: ExternalPaymentStoring,
        incomingPaymentStore: IncomingPaymentStoring,
        incomingPaymentSecretStore: IncomingPaymentSecretStoring,
        incomingPaymentAcknowledger: IncomingPaymentAcknowledging,
        backgroundExecutor: any BackgroundExecuting,
        recyclingStrategySettings: any CoinageRecyclingStrategyProviding,
        personOriginProvider: any OriginPersonProviding,
        viewFunctionFetcher: any ViewFunctionFetching,
        logger: SDKLoggerProtocol
    ) -> CoinageService {
        let operationQueue = OperationQueue()

        guard let connection = chainResource.getRpcConnection(for: chain.chainId) else {
            fatalError("Failed to get RPC connection for chain \(chain.chainId)")
        }
        guard let runtimeService = chainResource.getRuntimeCodingService(for: chain.chainId) else {
            fatalError("Failed to get runtime service for chain \(chain.chainId)")
        }

        let coinRepository = databaseFactory.makeCoinRepository()
        let trackedVoucherRepository = databaseFactory.makeTrackedVoucherRepository()
        let voucherRepository = databaseFactory.makeVoucherRepository()

        let voucherIndexstore = VoucherIndexstore(storage: keystore)
        let coinsIndexstore = CoinIndexstore(storage: keystore)
        let coinKeypairFactory = CoinKeypairFactory(entropyManager: rootEntropyManager)
        let voucherKeypairFactory = VoucherKeypairFactory(entropyManager: rootEntropyManager)
        // One allocator per Coinage instance: actor isolation serialises the index counter only
        // within a single instance.
        let coinAllocator = CoinAllocator(
            storage: coinsIndexstore,
            coinRepository: coinRepository,
            keyFactory: coinKeypairFactory
        )
        let voucherAllocator = VoucherAllocator(
            storage: voucherIndexstore,
            delayProvider: VoucherDelayProvider(),
            voucherRepository: voucherRepository,
            keyFactory: voucherKeypairFactory
        )

        // One minter per Coinage instance wraps both allocators; every mint site goes through it.
        let coinageMinter = CoinageMinter(coinAllocator: coinAllocator, voucherAllocator: voucherAllocator)

        let coinService = CoinService(databaseFactory: databaseFactory)

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let contextLoader = DenominationContextLoader(
            instanceId: instanceId,
            connection: connection,
            storageRequestFactory: storageRequestFactory,
            runtimeService: runtimeService
        )

        let readinessLoader = RecyclerReadinessLoader(
            instanceId: instanceId,
            connection: connection,
            runtimeCodingService: runtimeService,
            operationQueue: operationQueue
        )

        let coinSelector = CoinSelector()

        let blockNumberProvider = BlockInfoProvider(
            chainRegistry: chainResource,
            operationQueue: operationQueue,
            chainId: chain.chainId
        )

        let coinOnChainQuery = CoinOnChainQueryService(
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory
        )

        let voucherOnChainQuery = VoucherOnChainQueryService(
            instanceId: instanceId,
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory,
            publicKeyProvider: { try voucherKeypairFactory.derivePublicKey(index: $0) },
            aliasProvider: { try voucherKeypairFactory.alias(for: $0) }
        )

        let watchedEntries = CoinageTrackingTxSet()

        let chainFactory = CoinageChainViewFactory(
            coinQuery: coinOnChainQuery,
            voucherQuery: voucherOnChainQuery,
            blockInfoProvider: blockNumberProvider,
            blockEvents: CoinageChainViewFactory.BlockEventsDependencies(
                connection: connection,
                runtimeService: runtimeService,
                operationQueue: operationQueue,
                storageRequestFactory: storageRequestFactory
            ),
            logger: logger
        )

        let recoveryPass = RecoveryPass(
            store: txStore,
            chainFactory: chainFactory,
            watched: watchedEntries,
            logger: logger
        )

        let registrar = CoinageTxRegistrar(
            store: txStore,
            validator: CoinageTxRegistrationValidator(),
            watched: watchedEntries,
            logger: logger
        )

        let submissionWatcher = CoinageTxTracker(
            submitter: extrinsicSubmitter,
            store: txStore,
            chainFactory: chainFactory,
            watched: watchedEntries,
            backgroundExecutor: backgroundExecutor,
            logger: logger
        )

        let txService = CoinageTxService(
            store: txStore,
            registrar: registrar,
            watcher: submissionWatcher,
            pass: recoveryPass,
            operationFactory: extrinsicOperationFactory,
            chainFactory: chainFactory,
            logger: logger
        )

        let voucherLoaderFactory = VoucherLoaderFactory(
            instanceId: instanceId,
            minter: coinageMinter,
            keypairFactory: voucherKeypairFactory,
            txService: txService,
            originCreating: originFactory,
            runtimeService: runtimeService,
            chain: chain,
            logger: logger
        )
        let voucherService = VoucherService(
            databaseFactory: databaseFactory,
            trackedVoucherRepository: trackedVoucherRepository,
            voucherLoaderFactory: voucherLoaderFactory
        )

        // Shared unload-quota tracker: read by the recycling strategy's quota valve and decremented by the
        // unload paths (transfer / external payment) as free-unload tokens are spent.
        let consumedTokenChecker = ConsumedTokenChecker(
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeService
        )
        let quotaTracker = UnloadQuotaTracker(
            runtimeCodingService: runtimeService,
            consumedTokenChecker: consumedTokenChecker,
            personOriginProvider: personOriginProvider,
            viewFunctionFetcher: viewFunctionFetcher
        )

        let planFactory = TransferPlanFactory(
            instanceId: instanceId,
            minter: coinageMinter,
            voucherKeyFactory: voucherKeypairFactory,
            coinKeyFactory: coinKeypairFactory,
            durability: txService,
            originFactory: originFactory,
            quotaTracker: quotaTracker,
            recyclerLoader: readinessLoader,
            blockInfoProvider: blockNumberProvider,
            logger: logger
        )

        let memoBuilder = MemoBuilder(
            privateKeyDeriver: coinKeypairFactory
        )

        let senderService = TransferSenderService(
            coinSelector: coinSelector,
            planFactory: planFactory,
            memoBuilder: memoBuilder,
            recyclerLoader: readinessLoader,
            logger: logger
        )

        let recoveryService = CoinageBackupRecoveryService(
            coinIndexstore: coinsIndexstore,
            voucherIndexstore: voucherIndexstore,
            coinKeypairFactory: coinKeypairFactory,
            coinOnChainQuery: coinOnChainQuery,
            voucherOnChainQuery: voucherOnChainQuery,
            logger: logger
        )

        let transferSubmitter = CoinTransferSubmitter(
            originFactory: originFactory,
            extrinsicMonitor: extrinsicMonitorFactory
        )

        let claimSubmitter = CoinageClaimSubmitter(
            minter: coinageMinter,
            originFactory: originFactory,
            txService: txService,
            logger: logger
        )

        let claimCoinsService = ClaimCoinsService(
            txService: txService,
            coinOnChainQuery: coinOnChainQuery,
            claimSubmitter: claimSubmitter,
            snKeyFactory: SNKeyFactory(),
            coinService: coinService,
            logger: logger
        )

        let recipientService = TransferRecipientService(
            coinMinter: coinageMinter,
            coinKeyFactory: coinKeypairFactory,
            coinService: coinService,
            coinOnChainQuery: coinOnChainQuery,
            transferSubmitter: transferSubmitter,
            snKeyFactory: SNKeyFactory(),
            claimCoinsService: claimCoinsService,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let coinStateSyncService = CoinStateSyncService(
            coinService: coinService,
            databaseFactory: databaseFactory,
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )

        let voucherLocationService = VoucherLocationService(
            instanceId: instanceId,
            voucherRepository: voucherRepository,
            databaseFactory: databaseFactory,
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )

        let recyclingService = CoinageRecyclingService(
            voucherMinter: coinageMinter,
            coinKeypairFactory: coinKeypairFactory,
            voucherKeypairFactory: voucherKeypairFactory,
            txService: txService,
            originFactory: originFactory,
            backgroundExecutor: backgroundExecutor,
            logger: logger
        )

        // Recycling strategy evaluation collaborators. The evaluator itself is built lazily once the
        // denomination context resolves (see `CoinageService.setup`).
        let ringCapacityProvider = RingCapacityProvider(
            instanceId: instanceId,
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeService
        )
        let recyclingStrategyResolver = RecyclingStrategyProvider(quotaTracker: quotaTracker)
        let preClassificator = CoinageAssetPreClassificator()

        // Strategy-aware selection for product payments; reads verdicts through the coinage service
        // once it exists (set below), so before the first evaluation the planner reschedules.
        let spendableAssetsProvider = RecyclingAwareSpendableAssetsProvider(
            coinService: coinService,
            voucherService: voucherService,
            settings: recyclingStrategySettings,
            strategyResolver: recyclingStrategyResolver,
            ringCapacityProvider: ringCapacityProvider,
            preClassificator: preClassificator
        )

        let externalPaymentDependency = ExternalPaymentDependency(
            instanceId: instanceId,
            spendableAssets: spendableAssetsProvider,
            recycler: recyclingService,
            voucherService: voucherService,
            voucherKeyFactory: voucherKeypairFactory,
            voucherMinter: coinageMinter,
            recyclerLoader: readinessLoader,
            extrinsicMonitor: extrinsicMonitorFactory,
            durability: txService,
            originFactory: originFactory,
            quotaTracker: quotaTracker,
            blockNumberProvider: blockNumberProvider
        )

        let externalPaymentService = ExternalPaymentService(
            store: externalPaymentStore,
            dependency: externalPaymentDependency,
            logger: logger
        )

        let transferStatusService = CoinageTransferStatusService(
            databaseFactory: databaseFactory,
            chainViewFactory: chainFactory,
            coinOnChainQuery: coinOnChainQuery,
            snKeyFactory: SNKeyFactory(),
            logger: logger
        )

        let assetsTracking = AssetBalanceTracker(
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory,
            logger: logger
        )

        let claimAssetService = ClaimAssetService(
            assetsTracking: assetsTracking,
            voucherLoaderFactory: voucherLoaderFactory,
            voucherService: voucherService,
            txService: txService,
            logger: logger
        )

        let incomingPaymentSourceResolver = IncomingPaymentSourceResolver(
            entropyManager: rootEntropyManager,
            snKeyFactory: SNKeyFactory()
        )

        let incomingPaymentService = IncomingPaymentService(
            store: incomingPaymentStore,
            secretStore: incomingPaymentSecretStore,
            sourceResolver: incomingPaymentSourceResolver,
            paymentContext: IncomingPaymentContext(logger: logger),
            claimCoinsService: claimCoinsService,
            claimAssetService: claimAssetService,
            verdictResolver: CoinageGroupVerdictResolver(
                txService: txService,
                coinService: coinService,
                voucherService: voucherService
            ),
            acknowledger: incomingPaymentAcknowledger,
            instanceId: instanceId,
            logger: logger
        )

        let coinageService = CoinageService(
            coinService: coinService,
            voucherService: voucherService,
            coinKeypairFactory: coinKeypairFactory,
            senderService: senderService,
            ongoingTransferService: recipientService,
            txService: txService,
            claimCoinsService: claimCoinsService,
            transferStatusService: transferStatusService,
            externalPaymentService: externalPaymentService,
            contextLoader: contextLoader,
            coinStateSyncService: coinStateSyncService,
            voucherLocationService: voucherLocationService,
            recyclingService: recyclingService,
            recyclingStrategySettings: recyclingStrategySettings,
            recyclingStrategyResolver: recyclingStrategyResolver,
            ringCapacityProvider: ringCapacityProvider,
            preClassificator: preClassificator,
            applicationStateStreamFactory: applicationStateStreamFactory,
            databaseFactory: databaseFactory,
            recoveryService: recoveryService,
            incomingPaymentService: incomingPaymentService,
            logger: logger
        )

        spendableAssetsProvider.setVerdictsReader(coinageService)

        return coinageService
    }
}

extension VoucherKeyDeriving {
    func alias(for index: DerivationIndex) throws -> Data {
        try createKeyManager(index: index)
            .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
    }
}
