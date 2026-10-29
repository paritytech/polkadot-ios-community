import Foundation
import FoundationExt

struct DeviceTransferClientDependencies {
    let storageFacade: StorageFacadeProtocol
    let collector: DeviceTransferChangesCollecting
    let remoteContactResolver: RemoteContactResolving
    let chatStateApplier: DeviceSyncChatStateApplying
    let coinageStateApplier: DeviceSyncCoinageStateApplying
    let contactsStorageService: ContactsLocalStorageServicing
    let checkpointStore: DeviceTransferCheckpointStoring
    let deviceKeyManager: DeviceEncryptionKeyManaging
    let updateIdProvider: DeviceSyncUpdateIdProviding
    let dateProvider: any DateProviding
    let fileLocator: DeviceSyncFileLocating
    let downloadsStore: AttachmentStoring
    let logger: LoggerProtocol
}

/// Transfer file channels stay out of the sibling registry, so app downloads never use them.
final class DeviceTransferClientFactory: @unchecked Sendable {
    private let dependencies: DeviceTransferClientDependencies

    init(dependencies: DeviceTransferClientDependencies) {
        self.dependencies = dependencies
    }
}

extension DeviceTransferClientFactory: DeviceTransferClientMaking {
    func makeClient(
        for role: DeviceTransferClientRole,
        flow: any DevicePeerConnectionFlowing
    ) -> any DeviceTransferClientProtocol {
        let requester = makeRequester(flow: flow)
        let inner: any DeviceTransferClientProtocol =
            switch role {
            case .sender:
                makeSenderClient(flow: flow)
            case let .receiver(senderInstallationId):
                DeviceTransferReceiverClient(
                    flow: flow,
                    senderInstallationId: senderInstallationId,
                    dependencies: makeReceiverDependencies(flow: flow, requester: requester)
                )
            }

        return DeviceTransferWithFilesClient(
            inner: inner,
            fileTransfer: makeFileTransfer(flow: flow, requester: requester)
        )
    }
}

private extension DeviceTransferClientFactory {
    func makeRequester(flow: any DevicePeerConnectionFlowing) -> DeviceSyncFileRequester {
        DeviceSyncFileRequester(flow: flow, downloadsStore: dependencies.downloadsStore, logger: dependencies.logger)
    }

    func makeSenderClient(flow: any DevicePeerConnectionFlowing) -> DeviceTransferSenderClient {
        DeviceTransferSenderClient(
            flow: flow,
            collector: dependencies.collector,
            dependencies: DeviceTransferSenderDependencies(
                deviceKeyManager: dependencies.deviceKeyManager,
                updateIdProvider: dependencies.updateIdProvider,
                dateProvider: dependencies.dateProvider,
                logger: dependencies.logger
            )
        )
    }

    func makeFileTransfer(
        flow: any DevicePeerConnectionFlowing,
        requester: DeviceSyncFileRequester
    ) -> DeviceSyncFileTransfer {
        DeviceSyncFileTransfer(
            flow: flow,
            provider: DeviceSyncFileProvider(
                flow: flow,
                locator: dependencies.fileLocator,
                logger: dependencies.logger
            ),
            requester: requester,
            registry: DeviceSyncFileChannelRegistry(),
            peerLogger: dependencies.logger
        )
    }

    func makeReceiverDependencies(
        flow: any DevicePeerConnectionFlowing,
        requester: DeviceSyncFileRequester
    ) -> DeviceTransferReceiverDependencies {
        let facade = dependencies.storageFacade
        let updateApplier = DeviceSyncIncomingUpdateApplier(
            remoteContactResolver: dependencies.remoteContactResolver,
            contactRepositoryFactory: ChatContactRepositoryFactory(storageFacade: facade),
            chatRepositoryFactory: ChatRepositoryFactory(storageFacade: facade),
            messageRepositoryFactory: SenderOrderChatMessageRepositoryFactory(storageFacade: facade),
            removedChatRepositoryFactory: RemovedChatRepositoryFactory(storageFacade: facade),
            chatStateApplier: dependencies.chatStateApplier,
            coinageStateApplier: dependencies.coinageStateApplier,
            flow: flow,
            contactsStorageService: dependencies.contactsStorageService,
            storageFacade: facade,
            peerLogger: dependencies.logger
        )

        return DeviceTransferReceiverDependencies(
            updateApplier: updateApplier,
            coinageStateApplier: dependencies.coinageStateApplier,
            checkpointStore: dependencies.checkpointStore,
            deviceKeyManager: dependencies.deviceKeyManager,
            filePuller: DeviceTransferFilePuller(
                scanner: DeviceTransferMissingFileScanner(
                    messageRepositoryFactory: ChatMessageRepositoryFactory(storageFacade: facade),
                    downloadsStore: dependencies.downloadsStore
                ),
                requester: requester,
                logger: dependencies.logger
            ),
            logger: dependencies.logger
        )
    }
}
