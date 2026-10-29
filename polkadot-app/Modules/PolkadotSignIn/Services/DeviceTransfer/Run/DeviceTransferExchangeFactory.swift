import Foundation
import FoundationExt

struct DeviceTransferExchangeDependencies {
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
final class DeviceTransferExchangeFactory: @unchecked Sendable {
    private let dependencies: DeviceTransferExchangeDependencies

    init(dependencies: DeviceTransferExchangeDependencies) {
        self.dependencies = dependencies
    }
}

extension DeviceTransferExchangeFactory: DeviceTransferExchangeMaking {
    func makeSenderConnection() -> DeviceTransferConnectionMaking {
        { [self] flow, _ in
            let requester = makeRequester(flow: flow)
            let exchange = try DeviceTransferSenderExchange(
                flow: flow,
                collector: dependencies.collector,
                deviceEncryptionKey: dependencies.deviceKeyManager.getOrCreatePrivateKey().rawRepresentation,
                dependencies: DeviceTransferSenderDependencies(
                    updateIdProvider: dependencies.updateIdProvider,
                    dateProvider: dependencies.dateProvider,
                    logger: dependencies.logger
                )
            )

            try await withFileTransfer(flow: flow, requester: requester) {
                try await exchange.run()
            }
        }
    }

    func makeReceiverConnection(senderInstallationId: Data) -> DeviceTransferConnectionMaking {
        { [self] flow, onEvent in
            let requester = makeRequester(flow: flow)
            let exchange = DeviceTransferReceiverExchange(
                flow: flow,
                senderInstallationId: senderInstallationId,
                dependencies: makeReceiverDependencies(flow: flow, requester: requester)
            )

            try await withFileTransfer(flow: flow, requester: requester) {
                try await exchange.run { onEvent(.progress($0)) }
            }
        }
    }
}

private extension DeviceTransferExchangeFactory {
    func makeRequester(flow: any DevicePeerConnectionFlowing) -> DeviceSyncFileRequester {
        DeviceSyncFileRequester(flow: flow, downloadsStore: dependencies.downloadsStore, logger: dependencies.logger)
    }

    func withFileTransfer(
        flow: any DevicePeerConnectionFlowing,
        requester: DeviceSyncFileRequester,
        _ body: () async throws -> Void
    ) async throws {
        let fileTransfer = DeviceSyncFileTransfer(
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
        await fileTransfer.start()

        do {
            try await body()
            await fileTransfer.close()
        } catch {
            await fileTransfer.close()
            throw error
        }
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
