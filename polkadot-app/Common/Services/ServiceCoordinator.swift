import Foundation
import Keystore_iOS
import Operation_iOS
import AssetExchange
import NovaCrypto
import CommonService
import ExtrinsicService
import KeyDerivation
import Coinage
import Products
import SubstrateSdk
import FoundationExt
import Individuality
import UniqueDevice

protocol ServiceCoordinatorProtocol: ApplicationServiceProtocol {
    var depositService: DepositServiceProtocol { get }
    var fiatOnrampService: FiatOnrampServicing { get }
    var fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol { get }
    var fiatOnrampStorage: FiatOnrampStoring { get }
    var polkadotHandshakeService: PolkadotHandshakeServicing { get }
    var chatExtensionsRegistry: ChatExtensionsRegistering { get }
    var signInHostCoordinator: MessageExchangeSignInHostCoordinating { get }
    var chatCoordinator: MessageExchangeChatCoordinating { get }
    var callCoordinator: CallCoordinating { get }
    var attachmentUploadService: AttachmentUploadingServicing { get }
    var attachmentDownloadService: AttachmentDownloadingServicing { get }
    var audioSessionManager: AudioSessionManaging { get }
    var determineStateSyncService: DetermineStateSyncServicing { get }
    var personDataStore: DetermineStatePersonDataStore { get }
    var coinageService: CoinageServicing { get }
    var coinageBackupSyncService: CoinageBackupSyncServicing { get }
    var spentCoinsRecoveryService: SpentCoinsRecoveryServicing { get }
    var accountManager: ProductsAccountManaging { get }
    var allowanceManagerFacade: AllowanceManagerFacade { get }
    var turnService: TURNCredentialsProviding { get }
}

final class ServiceCoordinator {
    let chatCoordinator: MessageExchangeChatCoordinating
    let depositService: DepositServiceProtocol
    let fiatOnrampService: FiatOnrampServicing
    let fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol
    let fiatOnrampStorage: FiatOnrampStoring
    let polkadotHandshakeService: PolkadotHandshakeServicing
    let signInHostCoordinator: MessageExchangeSignInHostCoordinating
    let chatExtensionsRegistry: ChatExtensionsRegistering
    let callCoordinator: CallCoordinating
    let chatRequestCoordinator: ChatRequestCoordinatorServicing
    let attachmentUploadService: AttachmentUploadingServicing
    let attachmentDownloadService: AttachmentDownloadingServicing
    let coinageTransferMonitor: CoinageTransferMonitoring
    let audioSessionManager: AudioSessionManaging
    let determineStateSyncService: DetermineStateSyncServicing
    let personhoodBackgroundService: PersonhoodBackgroundService
    let personDataStore: DetermineStatePersonDataStore
    let coinageBackupSyncService: CoinageBackupSyncServicing
    let spentCoinsRecoveryService: SpentCoinsRecoveryServicing
    let notificationBadgeSyncService: NotificationBadgeSyncService
    let accountManager: ProductsAccountManaging
    let allowanceManagerFacade: AllowanceManagerFacade
    let turnService: TURNCredentialsProviding
    let deviceSyncService: DeviceSyncServicing
    let logger: LoggerProtocol

    // Retained so the weakly-held dependency-locator entry stays alive for the product host.
    let paymentsSupport: PaymentsSupport

    var coinageService: CoinageServicing {
        paymentsSupport.coinageService
    }

    init(
        chatCoordinator: MessageExchangeChatCoordinating,
        depositService: DepositServiceProtocol,
        fiatOnrampService: FiatOnrampServicing,
        fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol,
        fiatOnrampStorage: FiatOnrampStoring,
        polkadotHandshakeService: PolkadotHandshakeServicing,
        signInHostCoordinator: MessageExchangeSignInHostCoordinating,
        chatExtensionsRegistry: ChatExtensionsRegistering,
        callCoordinator: CallCoordinating,
        chatRequestCoordinator: ChatRequestCoordinatorServicing,
        attachmentUploadService: AttachmentUploadingServicing,
        attachmentDownloadService: AttachmentDownloadingServicing,
        coinageTransferMonitor: CoinageTransferMonitoring,
        audioSessionManager: AudioSessionManaging,
        determineStateSyncService: DetermineStateSyncServicing,
        personhoodBackgroundService: PersonhoodBackgroundService,
        personDataStore: DetermineStatePersonDataStore,
        coinageBackupSyncService: CoinageBackupSyncServicing,
        spentCoinsRecoveryService: SpentCoinsRecoveryServicing,
        notificationBadgeSyncService: NotificationBadgeSyncService,
        accountManager: ProductsAccountManaging,
        allowanceManagerFacade: AllowanceManagerFacade,
        paymentsSupport: PaymentsSupport,
        turnService: TURNCredentialsProviding,
        deviceSyncService: DeviceSyncServicing,
        logger: LoggerProtocol
    ) {
        self.chatCoordinator = chatCoordinator
        self.depositService = depositService
        self.fiatOnrampService = fiatOnrampService
        self.fiatOnrampTrackingService = fiatOnrampTrackingService
        self.fiatOnrampStorage = fiatOnrampStorage
        self.polkadotHandshakeService = polkadotHandshakeService
        self.signInHostCoordinator = signInHostCoordinator
        self.chatExtensionsRegistry = chatExtensionsRegistry
        self.callCoordinator = callCoordinator
        self.chatRequestCoordinator = chatRequestCoordinator
        self.attachmentUploadService = attachmentUploadService
        self.attachmentDownloadService = attachmentDownloadService
        self.coinageTransferMonitor = coinageTransferMonitor
        self.audioSessionManager = audioSessionManager
        self.determineStateSyncService = determineStateSyncService
        self.personhoodBackgroundService = personhoodBackgroundService
        self.personDataStore = personDataStore
        self.coinageBackupSyncService = coinageBackupSyncService
        self.spentCoinsRecoveryService = spentCoinsRecoveryService
        self.notificationBadgeSyncService = notificationBadgeSyncService
        self.accountManager = accountManager
        self.allowanceManagerFacade = allowanceManagerFacade
        self.deviceSyncService = deviceSyncService
        self.logger = logger
        self.paymentsSupport = paymentsSupport
        self.turnService = turnService
    }
}

extension ServiceCoordinator: ServiceCoordinatorProtocol {
    func setup() {
        determineStateSyncService.setup()
        personhoodBackgroundService.setup()
        chatCoordinator.setup()
        chatExtensionsRegistry.discover()
        chatRequestCoordinator.setup()
        fiatOnrampTrackingService.setup()
        attachmentUploadService.setup()
        attachmentDownloadService.setup()
        notificationBadgeSyncService.setup()

        Task {
            await signInHostCoordinator.setup()
            await setupDeviceSyncService()

            // Setup coinage service with main asset from chain
            let chainRegistry = ChainRegistryFacade.sharedRegistry
            let mainAssetId = AppConfig.Assets.mainAsset

            guard
                let chain = chainRegistry.getChain(for: mainAssetId.chainId),
                let asset = chain.asset(for: mainAssetId.assetId)
            else {
                assertionFailure()
                return
            }
            do {
                try await coinageService.setup(with: asset)
            } catch {
                assertionFailure(error.localizedDescription)
            }
            // Recovering backup 1st
            await coinageBackupSyncService.setup()
            await spentCoinsRecoveryService.setup()
            await coinageTransferMonitor.setup()
            Logger.shared.debug(
                "[GameDebug] depositService.setup() — enabled to onboard deposit-wallet balances (e.g. airdrop CASH) into Coinage"
            )
            await depositService.setup()
            await coinageService.transferRecoveryService.recover()
        }
    }

    func throttle() {
        determineStateSyncService.throttle()
        personhoodBackgroundService.throttle()
        chatCoordinator.throttle()
        chatRequestCoordinator.throttle()
        fiatOnrampTrackingService.throttle()
        attachmentUploadService.throttle()
        attachmentDownloadService.throttle()
        notificationBadgeSyncService.throttle()

        Task {
            await deviceSyncService.throttle()
            await coinageBackupSyncService.throttle()
            await spentCoinsRecoveryService.throttle()
            await coinageTransferMonitor.throttle()
            await signInHostCoordinator.throttle()
            await depositService.throttle()
        }
    }
}

extension ServiceCoordinator {
    // swiftlint:disable:next function_body_length
    static func createDefault() -> ServiceCoordinatorProtocol? {
        let mainWallet = SelectedWallet.main
        let depositWallet = SelectedWallet.depositWallet

        let logger: LoggerProtocol = Logger.shared

        let chatCoordinatorFactory = MessageExchangeCoordinatorFactory()

        guard let allowanceManagerFacade = AllowanceManagerFacade.create() else {
            return nil
        }

        let allowanceSupport = AllowanceSupport(
            allowancePromptRouter: AllowancePromptRouter(),
            sssManager: allowanceManagerFacade.sssManager,
            bulletInManager: allowanceManagerFacade.bulletInManager,
            smartContractManager: allowanceManagerFacade.smartContractManager
        )

        let accountManager = ProductsAccountManager(
            entropyManager: RootEntropyManager.shared,
            allowanceSupport: allowanceSupport
        )

        let turnService = TURNCredentialsService(
            requestFactory: TURNCredentialsRequestFactory(),
            tokenProvider: JWTTokenManager.shared
        )

        let resourceKeyManager = ProductResourceKeyManager(
            keychain: Keychain(),
            userDefaults: SharedContainerGroup.userDefaults
        )

        let sponsorFactory = HostTransactionSponsorFactory(
            accountManager: accountManager,
            resourceKeyManager: resourceKeyManager,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            logger: logger
        )

        guard
            let signInHostCoordinator = createSignInHostCoordinator(
                factory: chatCoordinatorFactory,
                accountManager: accountManager,
                sponsorFactory: sponsorFactory,
                logger: logger
            ),
            let chatCoordinator = createChatCoordinator(factory: chatCoordinatorFactory, logger: logger),
            let coinageServices = createCoinageServices(),
            let depositService = createDepositService(
                walletToFund: depositWallet,
                walletToDeposit: depositWallet,
                coinageService: coinageServices.coinageService
            ),
            let mainChatEncryptorFactory = try? ChatEncryptionManager().makeEncryptorFactory(
                ownEncryptionKeyId: Chat.Contact.Own.main().encryptionKeyId
            ),
            let ssoEncryptorFactory = try? ChatEncryptionManager().makeEncryptorFactory(
                ownEncryptionKeyId: Chat.Contact.Own.sso().encryptionKeyId
            ),
            let attachmentUploadService = createAttachmentUploadService(
                bulletInManager: allowanceManagerFacade.bulletInManager
            ),
            let attachmentDownloadService = createAttachmentDownloadService(),
            let syncServiceResult = createDetermineStateSyncService(),
            let deviceSyncService = try? createDeviceSyncService(turnService: turnService, logger: logger)
        else {
            return nil
        }

        let spentCoinsRecoveryService = SpentCoinsRecoveryService(
            coinageService: coinageServices.coinageService
        )

        guard let personhoodServices = createPersonhoodServices(
            syncStateStore: syncServiceResult.syncStore
        ) else {
            return nil
        }

        let chatRequestCoordinator = createChatRequestCoordinator()
        let audioSessionManager = AudioSessionManager()

        let paymentsSupport = PaymentsSupport(coinageService: coinageServices.coinageService)

        let truApiDependencies = TruApiDependenciesLocator()
        truApiDependencies.setDependency(allowanceSupport)
        truApiDependencies.setDependency(paymentsSupport)
        RootDependencyLocator.setDependency(truApiDependencies)

        let chatExtensionsRegistry = createChatExtensionsRegistry(
            accountManager: accountManager,
            syncStore: syncServiceResult.syncStore,
            personDataStore: syncServiceResult.personDataStore,
            syncService: syncServiceResult.service,
            personhoodRegistrationService: personhoodServices.registrationService,
            claimStatusStore: coinageServices.claimStatusStore,
            audioSessionManager: audioSessionManager
        )

        let fiatOnrampConfiguration = MeldFiatOnrampConfiguration.prod
        let fiatOnrampStorage = FiatOnrampStorage()
        let fiatOnrampService = MeldFiatOnrampService(configuration: fiatOnrampConfiguration)
        let fiatOnrampTrackingService = FiatOnrampTrackingServicing(
            depositService: depositService,
            fiatOnrampService: fiatOnrampService,
            fiatOnrampStorage: fiatOnrampStorage,
            clock: ContinuousClock()
        )

        let callCoordinator = RealCallCoordinator(
            presentationManager: ChatChatCallPresentationManager(logger: logger),
            outboxService: chatCoordinator.outboxService,
            turnService: turnService,
            logger: logger
        )

        chatCoordinator.inboxService.setupCallCoordinator(callCoordinator)

        let notificationBadgeSyncService = NotificationBadgeSyncService(logger: logger)

        return ServiceCoordinator(
            chatCoordinator: chatCoordinator,
            depositService: depositService,
            fiatOnrampService: fiatOnrampService,
            fiatOnrampTrackingService: fiatOnrampTrackingService,
            fiatOnrampStorage: fiatOnrampStorage,
            polkadotHandshakeService: PolkadotHandshakeService(
                rootWallet: DynamicDerivedWallet(derivationPath: nil),
                identityWallet: mainWallet,
                chatEncryptorFactory: mainChatEncryptorFactory,
                ssoEncryptorFactory: ssoEncryptorFactory,
                sssManager: allowanceManagerFacade.sssManager
            ),
            signInHostCoordinator: signInHostCoordinator,
            chatExtensionsRegistry: chatExtensionsRegistry,
            callCoordinator: callCoordinator,
            chatRequestCoordinator: chatRequestCoordinator,
            attachmentUploadService: attachmentUploadService,
            attachmentDownloadService: attachmentDownloadService,
            coinageTransferMonitor: coinageServices.transferMonitor,
            audioSessionManager: audioSessionManager,
            determineStateSyncService: syncServiceResult.service,
            personhoodBackgroundService: personhoodServices.backgroundService,
            personDataStore: syncServiceResult.personDataStore,
            coinageBackupSyncService: coinageServices.backupSyncService,
            spentCoinsRecoveryService: spentCoinsRecoveryService,
            notificationBadgeSyncService: notificationBadgeSyncService,
            accountManager: accountManager,
            allowanceManagerFacade: allowanceManagerFacade,
            paymentsSupport: paymentsSupport,
            turnService: turnService,
            deviceSyncService: deviceSyncService,
            logger: logger
        )
    }
}

private extension ServiceCoordinator {
    static func createChatCoordinator(
        factory: MessageExchangeCoordinatorMaking,
        logger: LoggerProtocol
    ) -> MessageExchangeChatCoordinating? {
        do {
            return try factory.makeChatCoordinator()
        } catch {
            logger.error("Message exchange chat coordinator error: \(error)")
            return nil
        }
    }

    static func createSignInHostCoordinator(
        factory: MessageExchangeCoordinatorMaking,
        accountManager: ProductsAccountManaging,
        sponsorFactory: TransactionSponsorMaking,
        logger: LoggerProtocol
    ) -> MessageExchangeSignInHostCoordinating? {
        do {
            return try factory.makeSignInHostCoordinator(
                accountManager: accountManager,
                sponsorFactory: sponsorFactory
            )
        } catch {
            logger.error("Message exchange sign in host coordinator error: \(error)")
            return nil
        }
    }
}

private extension ServiceCoordinator {
    static func createChatRequestCoordinator() -> ChatRequestCoordinatorServicing {
        let storageFacade = UserDataStorageFacade.shared
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let logger = Logger.shared

        return ChatRequestCoordinatorService(
            contactsProviderFactory: ChatContactDataProviderFactory(
                repositoryFactory: ChatContactRepositoryFactory(storageFacade: storageFacade),
                operationQueue: operationQueue,
                logger: logger
            ),
            messageProviderFactory: ChatMessageDataProviderFactory(
                repositoryFactory: ChatMessageRepositoryFactory(storageFacade: storageFacade),
                operationQueue: operationQueue,
                logger: logger
            ),
            serviceFactory: ChatRequestServiceFactory(
                remoteContactResolver: CompoundRemoteContactResolver(
                    resolvers: [
                        playerContactOperation(chatChainId: AppConfig.Chains.usernameChain),
                        remoteAccountOperation(chatChainId: AppConfig.Chains.usernameChain)
                    ],
                    logger: Logger.shared
                )
            ),
            logger: Logger.shared
        )
    }

    static func playerContactOperation(chatChainId: ChainModel.Id) -> RemoteContactResolving {
        let identifierService = ChatIdentifierService(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            chain: chatChainId,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        return PlayerContactOperationFactory(
            gameVotesRepositoryFactory: GameVoteRepositoryFactory(),
            identifierService: identifierService
        )
    }

    static func remoteAccountOperation(chatChainId: ChainModel.Id) -> RemoteContactOperationMaking {
        RemoteContactOperationFactory(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            connectionChainId: chatChainId,
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )
    }
}

private extension ServiceCoordinator {
    static func createDepositService(
        walletToFund: WalletManaging,
        walletToDeposit: WalletManaging,
        coinageService: CoinageServicing
    ) -> DepositServiceProtocol? {
        let logger: LoggerProtocol = Logger.shared

        guard
            let accountToFund = try? walletToFund.getMultiSigner().getAccountId() else {
            logger.error("Missing or invalid public key id")
            return nil
        }

        let stateMediatory = AssetsExchangeStateMediator()
        let priceStore = AssetExchangePriceStore(
            priceLocalSubscriptionFactory: PriceProviderFactory.shared,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            logger: logger
        )

        let assetExchangeFactory = AssetExchangeServiceFactory(
            depositWallet: walletToDeposit,
            accountToFund: accountToFund,
            fundedAssetId: AppConfig.Assets.fundedAsset,
            hydrationChainId: AppConfig.Chains.swappingChain,
            ahChainId: AppConfig.Chains.fundingChain,
            usdtChainId: AppConfig.Chains.usdtChain,
            feePercentageBuffer: DepositServiceConstants.feeBufferPercentage,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            storageFacade: SubstrateDataStorageFacade.shared,
            exchangesStateMediator: stateMediatory,
            priceStore: priceStore,
            configManager: FirebaseFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )

        return try? DepositService(
            assetExchangeFactory: assetExchangeFactory,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            priceStore: priceStore,
            balanceTrackingFactory: BalanceTrackingFactory(),
            coinageService: coinageService,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )
    }
}

// MARK: - DetermineStateSyncService Creation

private extension ServiceCoordinator {
    static func createDetermineStateSyncService() -> (
        service: DetermineStateSyncService,
        syncStore: DetermineStateSyncStore,
        personDataStore: DetermineStatePersonDataStore
    )? {
        let logger = Logger.shared

        guard
            let mainAccountId = try? SelectedWallet.main.getRawPublicKey(),
            let candidateAccountId = try? SelectedWallet.candidate.getRawPublicKey(),
            let mobRuleAccountId = try? SelectedWallet.mobRuleAlias.getRawPublicKey(),
            let scoreAccountId = try? SelectedWallet.scoreAlias.getRawPublicKey(),
            let resourcesAccountId = try? SelectedWallet.resourcesAlias.getRawPublicKey()
        else {
            logger.error("Failed to get wallet account IDs for DetermineStateSyncService")
            return nil
        }

        let vrfManager = BandersnatchKeyManager.fullPerson()

        guard let memberKey = try? vrfManager.getMemberKey() else {
            logger.error("Failed to get member key for DetermineStateSyncService")
            return nil
        }

        let syncQueue = DispatchQueue(label: "io.polkadot.app.dims.service.queue")

        let personDataStore = DetermineStatePersonDataStore(
            candidateAccountId: candidateAccountId,
            logger: logger
        )

        let syncStore = DetermineStateSyncStore(logger: logger)

        let syncService = DetermineStateSyncService(
            walletAccountId: mainAccountId,
            candidateAccountId: candidateAccountId,
            mobRuleAccountId: mobRuleAccountId,
            scoreAccountId: scoreAccountId,
            resourcesAccountId: resourcesAccountId,
            memberKey: memberKey,
            chainId: AppConfig.Chains.usernameChain,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            observers: [syncStore, personDataStore],
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            proccessingQueue: syncQueue,
            logger: logger
        )

        return (service: syncService, syncStore: syncStore, personDataStore: personDataStore)
    }
}
