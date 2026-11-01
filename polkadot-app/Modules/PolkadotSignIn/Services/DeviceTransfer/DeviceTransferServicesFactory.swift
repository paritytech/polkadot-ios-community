import Foundation
import FoundationExt
import StatementStore
import ChainRegistry
import Coinage
import KeyDerivation

/// What the new phone's transfer screen drives; built when the screen opens and released with it.
struct DeviceTransferReceiverServices {
    let coordinator: DeviceTransferReceiverCoordinating
    let installationService: ActiveInstallationServicing
    let installationConfiguration: ActiveInstallationConfiguration
    let discoveryConfiguration: DeviceTransferDiscoveryConfiguration
}

protocol DeviceTransferReceiverServicesMaking {
    func makeReceiverServices() throws -> DeviceTransferReceiverServices
}

/// Builds the transfer services the same way device sync builds its own, without a `ServiceCoordinator`:
/// the transfer screens run before the dashboard.
struct DeviceTransferServicesFactory {
    let statusStore: InstallationStatusStoring
    let logger: LoggerProtocol
}

extension DeviceTransferServicesFactory: DeviceTransferReceiverServicesMaking {
    func makeReceiverServices() throws -> DeviceTransferReceiverServices {
        let installationFactory = ActiveInstallationServiceFactory(statusStore: statusStore, logger: logger)
        let installationConfiguration = try installationFactory.makeConfiguration()
        let installationService = installationFactory.makeService()
        let ownSignKeyId = try Chat.Contact.Own.main().signKeyId
        let runFactory = try makeRunFactory(
            connection: installationConfiguration.connection,
            ownSignKeyId: ownSignKeyId
        )

        let coordinator = DeviceTransferReceiverCoordinator(
            publisher: DeviceTransferRequestPublisher(
                keyScheduleFactory: makeKeyScheduleFactory(),
                deviceInfo: .current()
            ),
            installationObserver: installationService,
            runFactory: runFactory,
            finalizer: DeviceTransferFinalizer(
                installationPublisher: installationService,
                processedStore: DeviceTransferProcessedCoreDataStore(storageFacade: UserDataStorageFacade.shared),
                checkpointStore: DeviceTransferCheckpointStore(),
                logger: logger
            ),
            logger: logger
        )

        return DeviceTransferReceiverServices(
            coordinator: coordinator,
            installationService: installationService,
            installationConfiguration: installationConfiguration,
            discoveryConfiguration: DeviceTransferDiscoveryConfiguration(
                connection: installationConfiguration.connection,
                signer: installationConfiguration.signer
            )
        )
    }
}

enum DeviceTransferServicesError: Error {
    case attachmentStoreUnavailable
}

private extension DeviceTransferServicesFactory {
    func makeKeyScheduleFactory() -> DeviceTransferKeyScheduleMaking {
        DeviceTransferKeyScheduleFactory(entropyManager: RootEntropyManager.shared)
    }

    func makeRunFactory(connection: StatementStoreConnecting, ownSignKeyId: String) throws -> DeviceTransferRunMaking {
        let turnService = TURNCredentialsService(
            requestFactory: TURNCredentialsRequestFactory(),
            tokenProvider: JWTTokenManager.shared
        )
        let clientDependencies = try makeClientDependencies(ownSignKeyId: ownSignKeyId)

        return DeviceTransferRunFactory(
            configuration: DeviceTransferRunConfiguration(
                connection: connection,
                signerManager: ChatSignerManager(),
                ownSignKeyId: ownSignKeyId
            ),
            keyScheduleFactory: makeKeyScheduleFactory(),
            clientFactory: DeviceTransferClientFactory(dependencies: clientDependencies),
            webRTC: (WebRTCConfigFactory(turnService: turnService), WebRTCPeerConnectionFactoryProvider.make()),
            logger: logger
        )
    }

    func makeClientDependencies(ownSignKeyId: String) throws -> DeviceTransferClientDependencies {
        guard let uploadsStore = AttachmentStore.uploads(), let downloadsStore = AttachmentStore.dowloads() else {
            throw DeviceTransferServicesError.attachmentStoreUnavailable
        }

        let facade = UserDataStorageFacade.shared
        let storage = DeviceSyncServiceStorageDependencies()
        let remoteContactResolver = RemoteContactOperationFactory()

        return DeviceTransferClientDependencies(
            storageFacade: facade,
            collector: DeviceSyncOutgoingChangesCollector(
                deviceRepositoryFactory: storage.deviceRepositoryFactory,
                contactRepositoryFactory: storage.contactRepositoryFactory,
                messageRepositoryFactory: storage.messageRepositoryFactory,
                removedChatRepositoryFactory: storage.removedChatRepositoryFactory,
                chatStateCollector: DeviceSyncChatStateCollector(databaseService: facade.databaseService),
                coinageStateCollector: DeviceSyncCoinageStateCollector(databaseService: facade.databaseService),
                ownSignKeyIds: [ownSignKeyId]
            ),
            remoteContactResolver: remoteContactResolver,
            chatStateApplier: DeviceSyncChatStateApplier(
                databaseService: facade.databaseService,
                remoteContactResolver: remoteContactResolver,
                tldProvider: DotNsTldProviderFacade.shared,
                logger: logger
            ),
            coinageStateApplier: DeviceSyncCoinageStateApplier(
                databaseService: facade.databaseService,
                coinKeyDeriver: CoinKeypairFactory(entropyManager: RootEntropyManager.shared),
                transferStateStore: TransferStateCoreDataStore(storageFacade: facade),
                logger: logger
            ),
            contactsStorageService: ContactsLocalStorageService(),
            checkpointStore: DeviceTransferCheckpointStore(),
            deviceKeyManager: DeviceEncryptionKeyManager.shared,
            updateIdProvider: DeviceSyncUpdateIdProvider(),
            dateProvider: NowDateProvider(),
            fileLocator: DeviceSyncFileLocator(
                messageRepositoryFactory: storage.messageRepositoryFactory,
                uploadsStore: uploadsStore,
                downloadsStore: downloadsStore,
                logger: logger
            ),
            downloadsStore: downloadsStore,
            logger: logger
        )
    }
}
