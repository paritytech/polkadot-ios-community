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

public extension CoinageService {
    // swiftlint:disable:next function_body_length

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
    static func make(
        chainResource: ChainResourceProtocol,
        chain: ChainProtocol,
        databaseFactory: DatabaseDependencyFactoring,
        originFactory: OriginCreating,
        extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        rootEntropyManager: RootEntropyManaging,
        keystore: KeystoreProtocol,
        planStore: any ClaimPlanStoring,
        walStore: any TransferWALStoring,
        schedulerFactory: CoinRecycleSchedulerMaking,
        settingsManager: SettingsManagerProtocol,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        externalPaymentStore: ExternalPaymentStoring,
        recyclingInterval: TimeInterval = CoinageConstants.recyclingInterval,
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
        let coinStateRepository = databaseFactory.makeCoinStateRepository()
        let voucherRepository = databaseFactory.makeVoucherRepository()
        let voucherLocationRepository = databaseFactory.makeVoucherLocationRepository()

        let voucherIndexstore = VoucherIndexstore(storage: keystore)
        let coinsIndexstore = CoinIndexstore(storage: keystore)
        let voucherAllocator = VoucherAllocator(
            storage: voucherIndexstore,
            delayProvider: VoucherDelayProvider()
        )

        let voucherKeypairFactory = VoucherKeypairFactory(entropyManager: rootEntropyManager)

        let voucherLoaderFactory = VoucherLoaderFactory(
            allocator: voucherAllocator,
            keypairFactory: voucherKeypairFactory,
            extrinsicSubmitMonitor: extrinsicMonitorFactory,
            originCreating: originFactory,
            runtimeService: runtimeService,
            chain: chain,
            logger: logger
        )
        let voucherService = VoucherService(
            voucherRepository: voucherRepository,
            voucherLoaderFactory: voucherLoaderFactory
        )
        let coinService = CoinService(
            coinRepository: coinRepository,
            coinStateRepository: coinStateRepository
        )
        let contextLoader = DenominationContextLoader(runtimeService: runtimeService)

        let readinessLoader = RecyclerReadinessLoader(
            connection: connection,
            runtimeCodingService: runtimeService,
            operationQueue: operationQueue
        )

        let coinSelector = CoinSelector()

        let coinKeypairFactory = CoinKeypairFactory(entropyManager: rootEntropyManager)

        let blockNumberProvider = BlockInfoProvider(
            chainRegistry: chainResource,
            operationQueue: operationQueue,
            chainId: chain.chainId
        )

        let submissionCoordinator = ExtrinsicSubmissionCoordinator(
            monitor: extrinsicMonitorFactory,
            walStore: walStore,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let planFactory = TransferPlanFactory(
            coinAllocator: CoinAllocator(storage: coinsIndexstore),
            voucherKeyFactory: voucherKeypairFactory,
            coinKeyFactory: coinKeypairFactory,
            coordinator: submissionCoordinator,
            originFactory: originFactory,
            recyclerLoader: readinessLoader,
            walStore: walStore,
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
            publicKeyProvider: { try voucherKeypairFactory.derivePublicKey(placeholderIndex: $0) },
            aliasProvider: { try voucherKeypairFactory.alias(for: $0) }
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
            extrinsicMonitor: extrinsicMonitorFactory,
            coinKeyFactory: coinKeypairFactory
        )

        let recipientService = TransferRecipientService(
            coinAllocator: CoinAllocator(storage: coinsIndexstore),
            coinKeyFactory: coinKeypairFactory,
            coinService: coinService,
            coinOnChainQuery: coinOnChainQuery,
            transferSubmitter: transferSubmitter,
            snKeyFactory: SNKeyFactory(),
            planStore: planStore,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let transferRecoveryService = TransferRecoveryService(
            walStore: walStore,
            coinService: coinService,
            voucherService: voucherService,
            coinQuery: coinOnChainQuery,
            voucherQuery: voucherOnChainQuery,
            coinKeyFactory: coinKeypairFactory,
            voucherKeyFactory: voucherKeypairFactory,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let coinProvider = databaseFactory.makeCoinProvider()
        let coinStateSyncService = CoinStateSyncService(
            coinService: coinService,
            coinProvider: coinProvider,
            connection: connection,
            runtimeService: runtimeService,
            entropyManager: rootEntropyManager,
            logger: logger
        )

        let voucherProvider = databaseFactory.makeVoucherProvider()
        let voucherLocationService = VoucherLocationService(
            voucherRepository: voucherLocationRepository,
            voucherProvider: voucherProvider,
            connection: connection,
            runtimeService: runtimeService,
            entropyManager: rootEntropyManager,
            logger: logger
        )

        let recyclingService = CoinageRecyclingService(
            schedulerFactory: schedulerFactory,
            settingsManager: settingsManager,
            coinService: coinService,
            voucherAllocator: voucherAllocator,
            voucherRepository: voucherRepository,
            coinKeypairFactory: coinKeypairFactory,
            voucherKeypairFactory: voucherKeypairFactory,
            extrinsicMonitorFactory: extrinsicMonitorFactory,
            originFactory: originFactory,
            connection: connection,
            logger: logger,
            recyclingInterval: recyclingInterval,
            recycleAtAge: CoinageConstants.recycleAtAge
        )

        let externalPaymentDependency = ExternalPaymentDependency(
            coinService: coinService,
            voucherService: voucherService,
            recycler: recyclingService,
            voucherKeyFactory: voucherKeypairFactory,
            voucherAllocator: voucherAllocator,
            recyclerLoader: readinessLoader,
            extrinsicMonitor: extrinsicMonitorFactory,
            walStore: walStore,
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
            transferRecoveryService: transferRecoveryService,
            externalPaymentService: externalPaymentService,
            contextLoader: contextLoader,
            coinStateSyncService: coinStateSyncService,
            voucherLocationService: voucherLocationService,
            recyclingService: recyclingService,
            applicationStateStreamFactory: applicationStateStreamFactory,
            coinProvider: coinProvider,
            voucherProvider: voucherProvider,
            recoveryService: recoveryService,
            logger: logger
        )

        return coinageService
    }
}

extension VoucherKeyDeriving {
    func alias(for index: UInt32) throws -> Data {
        let voucher = Voucher(
            exponent: 0,
            derivationIndex: index,
            allocatedAt: .now,
            readyAt: .now
        )
        return try createKeyManager(for: voucher)
            .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
    }
}
