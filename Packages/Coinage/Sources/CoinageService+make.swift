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

public extension CoinageService {
    /// Creates a CoinageService instance.
    ///
    /// - Parameters:
    ///   - chainResource: Chain resource for RPC connections
    ///   - chain: The chain configuration
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
        databaseFactory: DatabaseDependencyFactoring,
        originFactory: OriginCreating,
        extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        rootEntropyManager: RootEntropyManaging,
        keystore: KeystoreProtocol,
        planStore: any ClaimPlanStoring,
        durabilityStore: any CoinageTxRepositoryProtocol,
        schedulerFactory: CoinRecycleSchedulerMaking,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        externalPaymentStore: ExternalPaymentStoring,
        backgroundRecyclingInterval: TimeInterval = CoinageConstants.backgroundRecyclingInterval,
        backgroundExecutor: any BackgroundExecuting,
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
        let trackedCoinRepository = databaseFactory.makeTrackedCoinRepository()
        let trackedVoucherRepository = databaseFactory.makeTrackedVoucherRepository()
        let voucherRepository = databaseFactory.makeVoucherRepository()
        let voucherLocationRepository = databaseFactory.makeVoucherLocationRepository()

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

        let voucherLoaderFactory = VoucherLoaderFactory(
            minter: coinageMinter,
            keypairFactory: voucherKeypairFactory,
            extrinsicSubmitMonitor: extrinsicMonitorFactory,
            originCreating: originFactory,
            runtimeService: runtimeService,
            chain: chain,
            logger: logger
        )
        let voucherService = VoucherService(
            trackedVoucherRepository: trackedVoucherRepository,
            voucherLoaderFactory: voucherLoaderFactory
        )
        let coinService = CoinService(
            coinRepository: coinRepository,
            trackedCoinRepository: trackedCoinRepository
        )
        let contextLoader = DenominationContextLoader(runtimeService: runtimeService)

        let readinessLoader = RecyclerReadinessLoader(
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

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let coinOnChainQuery = CoinOnChainQueryService(
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory
        )

        let voucherOnChainQuery = VoucherOnChainQueryService(
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
            coinKeyFactory: coinKeypairFactory,
            blockInfoProvider: blockNumberProvider,
            blockEvents: CoinageChainViewFactory.BlockEventsDependencies(
                connection: connection,
                runtimeService: runtimeService,
                operationQueue: operationQueue,
                storageRequestFactory: storageRequestFactory
            ),
            logger: logger
        )

        let statusTransaction = StatusUpdateTransaction(
            store: durabilityStore,
            watched: watchedEntries,
            logger: logger
        )

        let recoveryPass = RecoveryPass(
            store: durabilityStore,
            chainFactory: chainFactory,
            watched: watchedEntries,
            transaction: statusTransaction,
            logger: logger
        )

        let registrar = CoinageTxRegistrar(
            store: durabilityStore,
            validator: CoinageTxRegistrationValidator(
                coinKeyDeriver: coinKeypairFactory,
                voucherKeyDeriver: voucherKeypairFactory
            ),
            chainFactory: chainFactory,
            watched: watchedEntries,
            mortality: CoinageConstants.entryMortality,
            logger: logger
        )

        let submissionWatcher = CoinageTxTracker(
            monitor: extrinsicMonitorFactory,
            store: durabilityStore,
            chainFactory: chainFactory,
            watched: watchedEntries,
            transaction: statusTransaction,
            backgroundExecutor: backgroundExecutor,
            onRelease: { [weak recoveryPass] in
                Task { await recoveryPass?.run() }
            },
            logger: logger
        )

        let durabilityService = CoinageTxService(
            store: durabilityStore,
            registrar: registrar,
            watcher: submissionWatcher,
            pass: recoveryPass,
            chainFactory: chainFactory,
            logger: logger
        )

        let planFactory = TransferPlanFactory(
            minter: coinageMinter,
            voucherKeyFactory: voucherKeypairFactory,
            coinKeyFactory: coinKeypairFactory,
            durability: durabilityService,
            originFactory: originFactory,
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

        let recipientService = TransferRecipientService(
            coinMinter: coinageMinter,
            coinKeyFactory: coinKeypairFactory,
            coinService: coinService,
            coinOnChainQuery: coinOnChainQuery,
            transferSubmitter: transferSubmitter,
            snKeyFactory: SNKeyFactory(),
            planStore: planStore,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let coinStateSyncService = CoinStateSyncService(
            coinService: coinService,
            coinProvider: databaseFactory.makeTrackedCoinProvider(),
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )

        let voucherProvider = databaseFactory.makeVoucherProvider()
        let voucherLocationService = VoucherLocationService(
            voucherRepository: voucherLocationRepository,
            voucherProvider: voucherProvider,
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )

        let recyclingService = CoinageRecyclingService(
            schedulerFactory: schedulerFactory,
            coinService: coinService,
            voucherMinter: coinageMinter,
            coinKeypairFactory: coinKeypairFactory,
            voucherKeypairFactory: voucherKeypairFactory,
            durability: durabilityService,
            originFactory: originFactory,
            logger: logger,
            backgroundRecyclingInterval: backgroundRecyclingInterval,
            recycleAtAge: CoinageConstants.recycleAtAge
        )

        let externalPaymentDependency = ExternalPaymentDependency(
            coinService: coinService,
            voucherService: voucherService,
            recycler: recyclingService,
            voucherKeyFactory: voucherKeypairFactory,
            voucherMinter: coinageMinter,
            recyclerLoader: readinessLoader,
            extrinsicMonitor: extrinsicMonitorFactory,
            durability: durabilityService,
            originFactory: originFactory,
            blockNumberProvider: blockNumberProvider
        )

        let externalPaymentService = ExternalPaymentService(
            store: externalPaymentStore,
            dependency: externalPaymentDependency,
            logger: logger
        )

        let coinageService = CoinageService(
            coinService: coinService,
            voucherService: voucherService,
            coinKeypairFactory: coinKeypairFactory,
            senderService: senderService,
            ongoingTransferService: recipientService,
            durabilityService: durabilityService,
            externalPaymentService: externalPaymentService,
            contextLoader: contextLoader,
            coinStateSyncService: coinStateSyncService,
            voucherLocationService: voucherLocationService,
            recyclingService: recyclingService,
            applicationStateStreamFactory: applicationStateStreamFactory,
            trackedCoinProvider: databaseFactory.makeTrackedCoinProvider(),
            trackedVoucherProvider: databaseFactory.makeTrackedVoucherProvider(),
            recoveryService: recoveryService,
            logger: logger
        )

        return coinageService
    }
}

extension VoucherKeyDeriving {
    func alias(for index: DerivationIndex) throws -> Data {
        try createKeyManager(index: index)
            .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
    }
}
