@testable import polkadot_app
import AsyncExtensions
import Coinage
import CryptoKit
import Foundation
import FoundationExt
import Keystore_iOS
import Operation_iOS
import Testing

@Suite(.timeLimit(.minutes(1)))
final class DeviceTransferRunTests {
    private let sender = TransferStateTestWorld()
    private let receiver = TransferStateTestWorld()
    private let senderInstallationId = Data(repeating: 0x5E, count: 32)
    private let oldDeviceKey = Curve25519.KeyAgreement.PrivateKey()
    private let checkpointStore = DeviceTransferCheckpointStore(settingsManager: InMemorySettingsManager())
    private let senderKeyManager = DeviceEncryptionKeyManager(
        keychain: InMemoryKeychain(),
        encryptionStorage: FixedDeviceEncryptionStorage(),
        logger: MockLogger()
    )
    private let receiverKeyManager = DeviceEncryptionKeyManager(
        keychain: InMemoryKeychain(),
        encryptionStorage: FixedDeviceEncryptionStorage(),
        logger: MockLogger()
    )
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeviceTransferRunTests-\(UUID().uuidString)", isDirectory: true)
    private lazy var senderDownloads = AttachmentStore(baseDirectory: directory.appendingPathComponent("sender"))
    private lazy var receiverDownloads = AttachmentStore(baseDirectory: directory.appendingPathComponent("receiver"))

    init() async throws {
        try await sender.setup()
        try await receiver.setup()
        try senderKeyManager.importPrivateKey(oldDeviceKey.rawRepresentation)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("The new phone ends up with the history at the old order, the old device key and the settled claims")
    func transferMovesHistoryKeyAndClaims() async throws {
        let first = try await sender.chatManager.sendMessage(.text("first"), status: .outgoing(.sent))
        let claimed = try await sender.saveTransfer(.incoming, totalValue: 6)
        try await sender.store.updateIncoming(
            messageId: claimed.messageId,
            state: IncomingTransferState(status: .failed)
        )
        let progress = DeviceSyncTestEventRecorder<DeviceTransferProgress>()

        try await runTransfer(onProgress: { progress.record($0) })

        #expect(try await storedOrders(in: receiver) == storedOrders(in: sender))
        #expect(try await storedOrders(in: receiver).keys.contains(first.messageId))
        let claimState = try await receiver.transfer(claimed.messageId)?.state
        #expect(claimState == .incoming(IncomingTransferState(status: .failed)))
        #expect(try receiverKeyManager.getPublicKey() == oldDeviceKey.publicKey.rawRepresentation)
        let syncing = progress.snapshot.compactMap { progress -> (applied: Int, total: Int)? in
            guard case let .syncing(applied, total) = progress else { return nil }
            return (applied, total)
        }
        let lastSyncing = try #require(syncing.last)
        #expect(lastSyncing.applied >= lastSyncing.total)
    }

    @Test("Attachments the new phone lacks are pulled from the old one, with progress in bytes")
    func missingAttachmentsArePulled() async throws {
        let contents = try Data.randomOrError(of: 150 * 1_024)
        let fileVariant = try makeFileVariant(size: contents.count)
        try senderDownloads.store(attachment: contents, filename: fileVariant.filename)
        try await saveAttachmentMessage(fileVariant)
        let progress = DeviceSyncTestEventRecorder<DeviceTransferProgress>()

        try await runTransfer(onProgress: { progress.record($0) })

        #expect(try receiverDownloads.loadAttachment(by: fileVariant.filename) == contents)
        let size = UInt64(contents.count)
        #expect(progress.snapshot.last == .files(DeviceTransferFileProgress(receivedBytes: size, totalBytes: size)))
    }

    @Test("A reconnect resumes from the receiver's checkpoint and carries only later changes")
    func reconnectResumesFromCheckpoint() async throws {
        _ = try await sender.chatManager.sendMessage(.text("before"), status: .outgoing(.sent))
        try await runTransfer()
        try await Task.sleep(for: .milliseconds(5))

        let later = try await sender.chatManager.sendMessage(.text("after"), status: .outgoing(.sent))
        let secondConnection = try await runTransfer()

        #expect(await secondConnection.sentMessageIds() == [later.messageId])
    }

    @Test("A claim whose message never arrives keeps the checkpoint where it was")
    func waitingClaimHoldsCheckpoint() async throws {
        let (senderSide, receiverSide) = await LoopbackTransferFlow.makePair()
        var controls = await senderSide.transferControls.makeAsyncIterator()
        var acks = await senderSide.acks.makeAsyncIterator()
        let receiverClient = makeReceiverClient(flow: receiverSide, requester: makeRequester(flow: receiverSide))
        let receiving = Task { try await receiverClient.run { _ in } }

        _ = try await controls.next()
        try await senderSide.sendTransferControl(
            .senderStarted(deviceEncryptionKey: oldDeviceKey.rawRepresentation, totalChanges: 1)
        )
        try await senderSide.sendUpdate(Chat.DeviceSyncUpdate(id: 1, entities: [orphanClaim()], timePoint: 0))
        _ = try await acks.next()
        try await senderSide.sendUpdate(Chat.DeviceSyncUpdate(id: 2, entities: [], timePoint: 5_000))
        _ = try await acks.next()
        try await senderSide.sendTransferControl(.senderCompleted)
        try await receiving.value

        #expect(checkpointStore.checkpoint(for: senderInstallationId) == nil)
    }
}

private extension DeviceTransferRunTests {
    @discardableResult
    func runTransfer(
        onProgress: @escaping @Sendable (DeviceTransferProgress) -> Void = { _ in }
    ) async throws -> LoopbackTransferFlow {
        let (senderSide, receiverSide) = await LoopbackTransferFlow.makePair()
        let requester = makeRequester(flow: receiverSide)
        let senderFiles = makeFileTransfer(flow: senderSide, requester: makeRequester(flow: senderSide))
        let receiverFiles = makeFileTransfer(flow: receiverSide, requester: requester)
        await senderFiles.start()
        await receiverFiles.start()

        let senderClient = makeSenderClient(flow: senderSide)
        let receiverClient = makeReceiverClient(flow: receiverSide, requester: requester)

        async let sending: Void = senderClient.run { _ in }
        try await receiverClient.run { event in
            if case let .progress(progress) = event { onProgress(progress) }
        }
        try await sending

        await senderFiles.close()
        await receiverFiles.close()
        return senderSide
    }

    func makeRequester(flow: LoopbackTransferFlow) -> DeviceSyncFileRequester {
        DeviceSyncFileRequester(flow: flow, downloadsStore: receiverDownloads, logger: MockLogger())
    }

    func makeFileTransfer(flow: LoopbackTransferFlow, requester: DeviceSyncFileRequester) -> DeviceSyncFileTransfer {
        let locator = DeviceSyncFileLocator(
            messageRepositoryFactory: ChatMessageRepositoryFactory(storageFacade: sender.facade),
            uploadsStore: senderDownloads,
            downloadsStore: senderDownloads,
            logger: MockLogger()
        )

        return DeviceSyncFileTransfer(
            flow: flow,
            provider: DeviceSyncFileProvider(flow: flow, locator: locator, logger: MockLogger()),
            requester: requester,
            registry: DeviceSyncFileChannelRegistry(),
            peerLogger: MockLogger()
        )
    }

    func makeSenderClient(flow: LoopbackTransferFlow) -> DeviceTransferSenderClient {
        let facade = sender.facade
        let collector = DeviceSyncOutgoingChangesCollector(
            deviceRepositoryFactory: LocalDeviceRepositoryFactory(storageFacade: facade),
            contactRepositoryFactory: ChatContactRepositoryFactory(storageFacade: facade),
            messageRepositoryFactory: ChatMessageRepositoryFactory(storageFacade: facade),
            removedChatRepositoryFactory: RemovedChatRepositoryFactory(storageFacade: facade),
            chatStateCollector: DeviceSyncChatStateCollector(databaseService: facade.databaseService),
            coinageStateCollector: DeviceSyncCoinageStateCollector(databaseService: facade.databaseService),
            ownSignKeyIds: ["sign-key"]
        )

        return DeviceTransferSenderClient(
            flow: flow,
            sequencer: DeviceTransferSenderSequencer(
                collector: collector,
                dateProvider: NowDateProvider(),
                logger: MockLogger()
            ),
            dependencies: DeviceTransferSenderDependencies(
                deviceKeyManager: senderKeyManager,
                updateIdProvider: DeviceSyncUpdateIdProvider(settingsManager: InMemorySettingsManager())
            )
        )
    }

    func makeReceiverClient(
        flow: LoopbackTransferFlow,
        requester: DeviceSyncFileRequester
    ) -> DeviceTransferReceiverClient {
        let facade = receiver.facade
        let coinageStateApplier = DeviceSyncCoinageStateApplier(
            databaseService: facade.databaseService,
            coinKeyDeriver: CoinKeypairFactory(entropyManager: FixedRootEntropyManager()),
            transferStateStore: receiver.store,
            logger: MockLogger()
        )
        let updateApplier = DeviceSyncIncomingUpdateApplier(
            remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
            contactRepositoryFactory: ChatContactRepositoryFactory(storageFacade: facade),
            chatRepositoryFactory: ChatRepositoryFactory(storageFacade: facade),
            messageRepositoryFactory: SenderOrderChatMessageRepositoryFactory(
                storageFacade: facade,
                orderAllocator: InMemoryChatMessageOrderAllocator()
            ),
            removedChatRepositoryFactory: RemovedChatRepositoryFactory(storageFacade: facade),
            chatStateApplier: DeviceSyncChatStateApplier(
                databaseService: facade.databaseService,
                remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
                tldProvider: StubDotNsTldProvider(tld: "dot"),
                logger: MockLogger()
            ),
            coinageStateApplier: coinageStateApplier,
            flow: flow,
            contactsStorageService: ContactsLocalStorageService(storageFacade: facade, logger: MockLogger()),
            storageFacade: facade,
            peerLogger: MockLogger()
        )

        return DeviceTransferReceiverClient(
            flow: flow,
            senderInstallationId: senderInstallationId,
            dependencies: DeviceTransferReceiverDependencies(
                updateApplier: updateApplier,
                coinageStateApplier: coinageStateApplier,
                checkpointStore: checkpointStore,
                deviceKeyManager: receiverKeyManager,
                filePuller: DeviceTransferFilePuller(
                    scanner: DeviceTransferMissingFileScanner(
                        messageRepositoryFactory: ChatMessageRepositoryFactory(storageFacade: facade),
                        downloadsStore: receiverDownloads
                    ),
                    requester: requester,
                    logger: MockLogger()
                ),
                logger: MockLogger()
            )
        )
    }

    func storedOrders(in world: TransferStateTestWorld) async throws -> [String: UInt64] {
        let messages = try await ChatMessageRepositoryFactory(storageFacade: world.facade)
            .createRepository(forFilter: nil)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
        return Dictionary(uniqueKeysWithValues: messages.map { ($0.messageId, $0.order) })
    }

    func makeFileVariant(size: Int) throws -> ChatRemoteMessageContent.FileVariant {
        try .p2pMixnet(.init(
            identifier: Data.randomOrError(of: 32),
            claimTicket: Data.randomOrError(of: 32),
            node: .wssUrl("wss://hop.example"),
            meta: .general(.init(mimeType: "image/jpeg", fileSize: UInt32(size)))
        ))
    }

    func saveAttachmentMessage(_ fileVariant: ChatRemoteMessageContent.FileVariant) async throws {
        _ = try await sender.chatManager.sendMessage(
            .richText(.init(text: nil, attachments: [.remoteDownloadable(fileVariant)])),
            status: .incoming(.new)
        )
    }

    func orphanClaim() throws -> Chat.DeviceSyncEntity {
        let accountId = try #require(sender.chatManager.chatId.accountId)
        return .coinageMessagesStatusUpdated([
            Chat.DeviceSyncCoinageMessageStatusUpdate(
                chatId: .contact(accountId: accountId),
                messageId: "never-sent",
                status: .failed,
                claimedValue: nil
            )
        ])
    }
}

private struct FixedDeviceEncryptionStorage: DeviceEncryptionStoring {
    let deviceEncryptId = "transfer-test"
}

private actor LoopbackTransferFlow: DevicePeerConnectionFlowing {
    private let incomingUpdates = AsyncStream.makeStream(of: Chat.DeviceSyncUpdate.self)
    private let incomingAcks = AsyncStream.makeStream(of: Chat.DeviceSyncUpdateAck.self)
    private let incomingControls = AsyncStream.makeStream(of: DeviceTransferControl.self)
    private let channelStates = AsyncStream.makeStream(of: DeviceSyncDataChannelState.self)
    private var fileMessageContinuations: [AsyncStream<Chat.DeviceSyncFileMessage>.Continuation] = []
    private var peer: LoopbackTransferFlow?
    private var sentUpdates: [Chat.DeviceSyncUpdate] = []

    static func makePair() async -> (LoopbackTransferFlow, LoopbackTransferFlow) {
        let senderSide = LoopbackTransferFlow()
        let receiverSide = LoopbackTransferFlow()
        await senderSide.connect(to: receiverSide)
        await receiverSide.connect(to: senderSide)
        return (senderSide, receiverSide)
    }

    var updates: AnyAsyncSequence<Chat.DeviceSyncUpdate> { incomingUpdates.stream.eraseToAnyAsyncSequence() }
    var acks: AnyAsyncSequence<Chat.DeviceSyncUpdateAck> { incomingAcks.stream.eraseToAnyAsyncSequence() }
    var states: AnyAsyncSequence<DeviceSyncDataChannelState> { channelStates.stream.eraseToAnyAsyncSequence() }
    var transferControls: AnyAsyncSequence<DeviceTransferControl> {
        incomingControls.stream.eraseToAnyAsyncSequence()
    }

    /// Both the file transfer and the sender's idle wait read file messages, so each subscriber gets every one.
    var fileMessages: AnyAsyncSequence<Chat.DeviceSyncFileMessage> {
        let (stream, continuation) = AsyncStream.makeStream(of: Chat.DeviceSyncFileMessage.self)
        fileMessageContinuations.append(continuation)
        return stream.eraseToAnyAsyncSequence()
    }

    func start() async throws {}

    func sendFileMessage(_ message: Chat.DeviceSyncFileMessage) async throws {
        await peer?.receive(message)
    }

    func cancel() async {}

    func sendUpdate(_ update: Chat.DeviceSyncUpdate) async throws {
        sentUpdates.append(update)
        await peer?.receive(update)
    }

    func sendAck(_ ack: Chat.DeviceSyncUpdateAck) async throws {
        await peer?.receive(ack)
    }

    func sendTransferControl(_ control: DeviceTransferControl) async throws {
        await peer?.receive(control)
    }

    func sentMessageIds() -> [String] {
        sentUpdates.flatMap(\.entities).flatMap { entity -> [String] in
            guard case let .messages(messages) = entity else { return [] }
            return messages.map(\.remote.messageId)
        }
    }

    private func connect(to peer: LoopbackTransferFlow) {
        self.peer = peer
    }

    private func receive(_ update: Chat.DeviceSyncUpdate) {
        incomingUpdates.continuation.yield(update)
    }

    private func receive(_ ack: Chat.DeviceSyncUpdateAck) {
        incomingAcks.continuation.yield(ack)
    }

    private func receive(_ control: DeviceTransferControl) {
        incomingControls.continuation.yield(control)
    }

    private func receive(_ message: Chat.DeviceSyncFileMessage) {
        fileMessageContinuations.forEach { $0.yield(message) }
    }
}
