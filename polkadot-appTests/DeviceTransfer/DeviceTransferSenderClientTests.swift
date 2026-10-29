@testable import polkadot_app
import AsyncExtensions
import Foundation
import FoundationExt
import Keystore_iOS
import Operation_iOS
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferSenderClientTests {
    private let world = TransferStateTestWorld()
    private let allocator = InMemoryChatMessageOrderAllocator()

    init() async throws {
        try await world.setup()
    }

    @Test("A fresh transfer sends every message in pages, in the order they were stored, counted upfront")
    func freshTransferSendsEverything() async throws {
        try await saveMessages(["e", "d", "c", "b", "a"])
        let receiver = TransferReceiverFlow(resumeFrom: nil)

        try await makeClient(flow: receiver, pageSize: 2).run { _ in }

        #expect(await receiver.receivedMessageIds == ["e", "d", "c", "b", "a"])
        #expect(await receiver.announcedTotal == receiver.receivedItemCountInFirstRound)
        #expect(await receiver.sentCompletion)
    }

    @Test("Resuming from the receiver's checkpoint sends only what changed after it")
    func resumeSendsOnlyNewerChanges() async throws {
        try await saveMessages(["a", "b"])
        let firstConnection = TransferReceiverFlow(resumeFrom: nil)
        try await makeClient(flow: firstConnection).run { _ in }
        try await Task.sleep(for: .milliseconds(5))

        try await saveMessages(["c"])
        let secondConnection = await TransferReceiverFlow(resumeFrom: firstConnection.checkpoint)
        try await makeClient(flow: secondConnection).run { _ in }

        #expect(await secondConnection.receivedMessageIds == ["c"])
    }

    @Test("A message edited after the page cursor passed it is sent again in a later round")
    func messageEditedBehindCursorIsSentAgain() async throws {
        try await saveMessages(["m1", "m2", "m3"])
        let receiver = TransferReceiverFlow(resumeFrom: nil) { [self] in
            try await Task.sleep(for: .milliseconds(5))
            try await saveMessages(["m1"], text: "edited")
        }

        try await makeClient(flow: receiver, pageSize: 1).run { _ in }

        #expect(await receiver.receivedMessageIds.filter { $0 == "m1" }.count == 2)
        #expect(try #require(await receiver.checkpointWhenReceived["m1"]) > 0)
        #expect(await receiver.sentCompletion)
    }

    @Test("A receiver still pulling files keeps the sender waiting past the idle deadline")
    func filePullKeepsSenderWaiting() async throws {
        let receiver = TransferReceiverFlow(resumeFrom: nil, filePull: (requests: 5, interval: .milliseconds(100)))
        let settings = DeviceTransferSenderSettings(completionIdleTimeout: .milliseconds(250))

        try await makeClient(flow: receiver, settings: settings).run { _ in }

        #expect(await receiver.sentCompletion)
    }

    @Test("A receiver that goes quiet before confirming fails the run on the idle deadline")
    func quietReceiverFailsRun() async throws {
        let receiver = TransferReceiverFlow(resumeFrom: nil, filePull: (requests: 1, interval: .seconds(5)))
        let settings = DeviceTransferSenderSettings(completionIdleTimeout: .milliseconds(250))

        await #expect(throws: DeviceTransferRunError.timedOut) {
            try await makeClient(flow: receiver, settings: settings).run { _ in }
        }
    }

    @Test("An update the receiver never acknowledges fails the run")
    func unacknowledgedUpdateFailsRun() async throws {
        try await saveMessages(["a"])
        let receiver = TransferReceiverFlow(resumeFrom: nil, acknowledges: false)
        let settings = DeviceTransferSenderSettings(responseTimeout: .milliseconds(100))

        await #expect(throws: DeviceTransferRunError.timedOut) {
            try await makeClient(flow: receiver, settings: settings).run { _ in }
        }
    }
}

private extension DeviceTransferSenderClientTests {
    func makeClient(flow: TransferReceiverFlow, pageSize: Int = 200) -> DeviceTransferSenderClient {
        makeClient(flow: flow, settings: DeviceTransferSenderSettings(messagePageSize: pageSize))
    }

    func makeClient(
        flow: TransferReceiverFlow,
        settings: DeviceTransferSenderSettings
    ) -> DeviceTransferSenderClient {
        DeviceTransferSenderClient(
            flow: flow,
            collector: makeCollector(),
            deviceEncryptionKey: Data(repeating: 0x09, count: DeviceTransferControl.deviceEncryptionKeyLength),
            dependencies: DeviceTransferSenderDependencies(
                updateIdProvider: DeviceSyncUpdateIdProvider(settingsManager: InMemorySettingsManager()),
                dateProvider: NowDateProvider(),
                logger: MockLogger()
            ),
            settings: settings
        )
    }

    func makeCollector() -> DeviceSyncOutgoingChangesCollector {
        DeviceSyncOutgoingChangesCollector(
            deviceRepositoryFactory: LocalDeviceRepositoryFactory(storageFacade: world.facade),
            contactRepositoryFactory: ChatContactRepositoryFactory(storageFacade: world.facade),
            messageRepositoryFactory: ChatMessageRepositoryFactory(storageFacade: world.facade),
            removedChatRepositoryFactory: RemovedChatRepositoryFactory(storageFacade: world.facade),
            chatStateCollector: DeviceSyncChatStateCollector(databaseService: world.facade.databaseService),
            coinageStateCollector: DeviceSyncCoinageStateCollector(databaseService: world.facade.databaseService),
            ownSignKeyIds: ["sign-key"]
        )
    }

    func saveMessages(_ messageIds: [String], text: String? = nil) async throws {
        let repository = world.facade
            .createRepository(mapper: AnyCoreDataMapper(ChatMessageEntityMapper(orderAllocator: allocator)))

        for messageId in messageIds {
            let message = Chat.LocalMessage(
                messageId: messageId,
                chatId: world.chatManager.chatId,
                origin: .user,
                creationSource: .localDevice,
                status: .outgoing(.sent),
                timestamp: 1_000,
                content: .text(text ?? messageId),
                reactions: [],
                compactionId: nil,
                relatedMessages: []
            )
            try await repository.saveOperation({ [message] }, { [] }).asyncExecute()
        }
    }
}

private actor TransferReceiverFlow: DevicePeerConnectionFlowing {
    private let resumePoint: UInt64?
    private let acknowledges: Bool
    private let filePull: (requests: Int, interval: Duration)?
    private var fileContinuations: [AsyncStream<Chat.DeviceSyncFileMessage>.Continuation] = []
    private var onFirstMessages: (@Sendable () async throws -> Void)?
    private var ackContinuation: AsyncStream<Chat.DeviceSyncUpdateAck>.Continuation?
    private var controlContinuation: AsyncStream<DeviceTransferControl>.Continuation?

    private(set) var announcedTotal: Int?
    private(set) var receivedItemCountInFirstRound = 0
    private(set) var receivedMessageIds: [String] = []
    private(set) var checkpointWhenReceived: [String: UInt64] = [:]
    private(set) var checkpoint: UInt64?
    private(set) var sentCompletion = false
    private var closedRounds = 0

    init(
        resumeFrom resumePoint: UInt64?,
        acknowledges: Bool = true,
        filePull: (requests: Int, interval: Duration)? = nil,
        onFirstMessages: (@Sendable () async throws -> Void)? = nil
    ) {
        self.resumePoint = resumePoint
        self.acknowledges = acknowledges
        self.filePull = filePull
        self.onFirstMessages = onFirstMessages
    }

    var updates: AnyAsyncSequence<Chat.DeviceSyncUpdate> { AsyncStream { _ in }.eraseToAnyAsyncSequence() }
    var states: AnyAsyncSequence<DeviceSyncDataChannelState> { AsyncStream { _ in }.eraseToAnyAsyncSequence() }
    var fileMessages: AnyAsyncSequence<Chat.DeviceSyncFileMessage> {
        let (stream, continuation) = AsyncStream.makeStream(of: Chat.DeviceSyncFileMessage.self)
        fileContinuations.append(continuation)
        return stream.eraseToAnyAsyncSequence()
    }

    var acks: AnyAsyncSequence<Chat.DeviceSyncUpdateAck> {
        let (stream, continuation) = AsyncStream.makeStream(of: Chat.DeviceSyncUpdateAck.self)
        ackContinuation = continuation
        return stream.eraseToAnyAsyncSequence()
    }

    var transferControls: AnyAsyncSequence<DeviceTransferControl> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceTransferControl.self)
        controlContinuation = continuation
        continuation.yield(.resume(fromTimePoint: resumePoint))
        return stream.eraseToAnyAsyncSequence()
    }

    func start() async throws {}
    func sendAck(_: Chat.DeviceSyncUpdateAck) async throws {}
    func sendFileMessage(_: Chat.DeviceSyncFileMessage) async throws {}
    func cancel() async {}

    func sendUpdate(_ update: Chat.DeviceSyncUpdate) async throws {
        record(update)

        if let hook = onFirstMessages, update.entities.contains(where: \.isMessages) {
            onFirstMessages = nil
            try await hook()
        }

        if acknowledges {
            ackContinuation?.yield(Chat.DeviceSyncUpdateAck(id: update.id))
        }
    }

    func sendTransferControl(_ control: DeviceTransferControl) async throws {
        switch control {
        case let .senderStarted(_, totalChanges):
            announcedTotal = Int(totalChanges)
        case .senderCompleted:
            sentCompletion = true
            if let filePull {
                Task { await pullFiles(filePull) }
            } else {
                controlContinuation?.yield(.receiverCompleted)
            }
        default:
            break
        }
    }

    private func pullFiles(_ filePull: (requests: Int, interval: Duration)) async {
        for requestId in 0 ..< filePull.requests {
            try? await Task.sleep(for: filePull.interval)
            let request = Chat.DeviceSyncFileMessage.AvailabilityRequest(requestId: UInt32(requestId), files: [])
            fileContinuations.forEach { $0.yield(.availabilityRequest(request)) }
        }
        controlContinuation?.yield(.receiverCompleted)
    }

    private func record(_ update: Chat.DeviceSyncUpdate) {
        guard !update.entities.isEmpty else {
            checkpoint = update.timePoint
            closedRounds += 1
            return
        }

        if closedRounds == 0 {
            receivedItemCountInFirstRound += update.entities.reduce(0) { $0 + $1.itemCount }
        }

        for case let .messages(messages) in update.entities {
            for message in messages {
                receivedMessageIds.append(message.remote.messageId)
                checkpointWhenReceived[message.remote.messageId] = checkpoint ?? 0
            }
        }
    }
}

private extension Chat.DeviceSyncEntity {
    var isMessages: Bool {
        if case .messages = self { return true }
        return false
    }
}
