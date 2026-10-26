@testable import polkadot_app
import AsyncExtensions
import Coinage
import CryptoKit
import Foundation
import FoundationExt
import Keystore_iOS
import Operation_iOS
import Testing

/// Old phone (`sender`) and new phone (`receiver`) are real in-memory stores sharing a chat, joined by a
/// loopback channel that runs both exchanges against each other.
@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferRunTests {
    private let sender = TransferStateTestWorld()
    private let receiver = TransferStateTestWorld()
    private let senderInstallationId = Data(repeating: 0x5E, count: 32)
    private let oldDeviceKey = Curve25519.KeyAgreement.PrivateKey()
    private let checkpointStore = DeviceTransferCheckpointStore(settingsManager: InMemorySettingsManager())
    private let receiverKeyManager = DeviceEncryptionKeyManager(
        keychain: InMemoryKeychain(),
        encryptionStorage: FixedDeviceEncryptionStorage(),
        logger: MockLogger()
    )

    init() async throws {
        try await sender.setup()
        try await receiver.setup()
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
        let last = try #require(progress.snapshot.last)
        #expect(last.applied >= last.total)
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
        let receiving = Task { try await makeReceiverExchange(flow: receiverSide).run { _ in } }

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
        onProgress: @escaping (DeviceTransferProgress) -> Void = { _ in }
    ) async throws -> LoopbackTransferFlow {
        let (senderSide, receiverSide) = await LoopbackTransferFlow.makePair()
        let senderExchange = makeSenderExchange(flow: senderSide)
        let receiverExchange = makeReceiverExchange(flow: receiverSide)

        async let sending: Void = senderExchange.run()
        try await receiverExchange.run(onProgress: onProgress)
        try await sending

        return senderSide
    }

    func makeSenderExchange(flow: LoopbackTransferFlow) -> DeviceTransferSenderExchange {
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

        return DeviceTransferSenderExchange(
            flow: flow,
            collector: collector,
            deviceEncryptionKey: oldDeviceKey.rawRepresentation,
            dependencies: DeviceTransferSenderDependencies(
                updateIdProvider: DeviceSyncUpdateIdProvider(settingsManager: InMemorySettingsManager()),
                dateProvider: NowDateProvider(),
                logger: MockLogger()
            )
        )
    }

    func makeReceiverExchange(flow: LoopbackTransferFlow) -> DeviceTransferReceiverExchange {
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

        return DeviceTransferReceiverExchange(
            flow: flow,
            senderInstallationId: senderInstallationId,
            dependencies: DeviceTransferReceiverDependencies(
                updateApplier: updateApplier,
                coinageStateApplier: coinageStateApplier,
                checkpointStore: checkpointStore,
                deviceKeyManager: receiverKeyManager,
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

/// One side of an in-process data channel: what one side sends, the other receives, in order.
private actor LoopbackTransferFlow: DevicePeerConnectionFlowing {
    private let incomingUpdates = AsyncStream.makeStream(of: Chat.DeviceSyncUpdate.self)
    private let incomingAcks = AsyncStream.makeStream(of: Chat.DeviceSyncUpdateAck.self)
    private let incomingControls = AsyncStream.makeStream(of: DeviceTransferControl.self)
    private let channelStates = AsyncStream.makeStream(of: DeviceSyncDataChannelState.self)
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

    var fileMessages: AnyAsyncSequence<Chat.DeviceSyncFileMessage> {
        AsyncStream<Chat.DeviceSyncFileMessage> { _ in }.eraseToAnyAsyncSequence()
    }

    func start() async throws {}
    func sendFileMessage(_: Chat.DeviceSyncFileMessage) async throws {}
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
}
