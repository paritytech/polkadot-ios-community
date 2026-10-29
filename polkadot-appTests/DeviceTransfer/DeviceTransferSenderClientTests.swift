@testable import polkadot_app
import AsyncExtensions
import Foundation
import FoundationExt
import Keystore_iOS
import Operation_iOS
import StructuredConcurrencyTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferSenderClientTests {
    private let world = TransferStateTestWorld()
    private let allocator = InMemoryChatMessageOrderAllocator()
    private let clock = ManualClock()
    /// Ahead of the wall clock, so every row the mappers stamp falls before the first round's end.
    private let sequencerDate = MockDateProvider(now: Date().addingTimeInterval(3_600))

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

    @Test("Within a round, claim statuses follow their messages, and the announced total counts them")
    func claimsFollowTheirMessages() async throws {
        try await saveMessages(["text"])
        let claimed = try await world.saveTransfer(.incoming, totalValue: 3)
        try await world.store.updateIncoming(
            messageId: claimed.messageId,
            state: IncomingTransferState(status: .failed)
        )
        let receiver = TransferReceiverFlow(resumeFrom: nil)

        try await makeClient(flow: receiver).run { _ in }

        let kinds = await receiver.firstRoundEntityKinds
        let lastMessages = try #require(kinds.lastIndex(of: "messages"))
        let claims = try #require(kinds.firstIndex(of: "coinageMessagesStatusUpdated"))
        #expect(lastMessages < claims)
        #expect(await receiver.announcedTotal == receiver.receivedItemCountInFirstRound)
    }

    @Test("Resuming from the receiver's checkpoint sends only what changed after it")
    func resumeSendsOnlyNewerChanges() async throws {
        try await saveMessages(["a", "b"])
        let firstConnection = TransferReceiverFlow(resumeFrom: nil)
        try await makeClient(flow: firstConnection).run { _ in }

        await sequencerDate.advance(by: 10)
        try await saveMessages(["c"])
        try await world.setModifiedAt(sequencerDate.read().addingTimeInterval(-5), of: "c")
        let secondConnection = await TransferReceiverFlow(resumeFrom: firstConnection.checkpoint)
        try await makeClient(flow: secondConnection).run { _ in }

        #expect(await secondConnection.receivedMessageIds == ["c"])
    }

    @Test("A message edited after the page cursor passed it is sent again in a later round")
    func messageEditedBehindCursorIsSentAgain() async throws {
        try await saveMessages(["m1", "m2", "m3"])
        let receiver = TransferReceiverFlow(resumeFrom: nil) { [self] in
            await sequencerDate.advance(by: 10)
            try await saveMessages(["m1"], text: "edited")
            try await world.setModifiedAt(sequencerDate.read().addingTimeInterval(-5), of: "m1")
        }

        try await makeClient(flow: receiver, pageSize: 1).run { _ in }

        #expect(await receiver.receivedMessageIds.filter { $0 == "m1" }.count == 2)
        #expect(try #require(await receiver.checkpointWhenReceived["m1"]) > 0)
        #expect(await receiver.sentCompletion)
    }

    @Test("Each file request from the receiver restarts the sender's idle wait for confirmation")
    func fileRequestsRestartIdleWait() async throws {
        let receiver = TransferReceiverFlow(resumeFrom: nil, confirmsCompletion: false)
        let idleTimeout = DeviceTransferConstants.runIdleTimeout
        let running = Task { try await makeClient(flow: receiver).run { _ in } }

        for requestId in 0 ..< 3 {
            await clock.waitForSleepStarts(for: idleTimeout, count: requestId + 1)
            await receiver.requestFiles(requestId: UInt32(requestId))
        }
        await clock.waitForSleepStarts(for: idleTimeout, count: 4)
        await receiver.confirmCompletion()

        try await running.value
    }

    @Test("A receiver that goes quiet before confirming fails the run on the idle deadline")
    func quietReceiverFailsRun() async throws {
        let receiver = TransferReceiverFlow(resumeFrom: nil, confirmsCompletion: false)
        let running = Task { try await makeClient(flow: receiver).run { _ in } }

        await clock.resumeSleep(for: DeviceTransferConstants.runIdleTimeout)

        await #expect(throws: DeviceTransferRunError.timedOut) { try await running.value }
        #expect(await receiver.sentCompletion)
    }

    @Test("An update the receiver never acknowledges fails the run")
    func unacknowledgedUpdateFailsRun() async throws {
        try await saveMessages(["a"])
        let receiver = TransferReceiverFlow(resumeFrom: nil, acknowledges: false)
        let running = Task { try await makeClient(flow: receiver).run { _ in } }

        _ = await receiver.sentUpdates.waitForCount(1)
        await clock.resumeSleep(for: DeviceTransferSenderSettings().responseTimeout)

        await #expect(throws: DeviceTransferRunError.timedOut) { try await running.value }
    }
}

private extension DeviceTransferSenderClientTests {
    func makeClient(
        flow: TransferReceiverFlow,
        pageSize: Int = DeviceTransferSenderSequencer.defaultMessagePageSize
    ) -> DeviceTransferSenderClient {
        DeviceTransferSenderClient(
            flow: flow,
            sequencer: DeviceTransferSenderSequencer(
                collector: makeCollector(),
                dateProvider: sequencerDate,
                messagePageSize: pageSize,
                logger: MockLogger()
            ),
            dependencies: DeviceTransferSenderDependencies(
                deviceKeyManager: StubDeviceEncryptionKeyManager(),
                updateIdProvider: DeviceSyncUpdateIdProvider(settingsManager: InMemorySettingsManager())
            ),
            settings: DeviceTransferSenderSettings(clock: clock)
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
    private let confirmsCompletion: Bool
    private var fileContinuations: [AsyncStream<Chat.DeviceSyncFileMessage>.Continuation] = []
    private var onFirstMessages: (@Sendable () async throws -> Void)?
    private var ackContinuation: AsyncStream<Chat.DeviceSyncUpdateAck>.Continuation?
    private var controlContinuation: AsyncStream<DeviceTransferControl>.Continuation?

    private(set) var announcedTotal: Int?
    private(set) var receivedItemCountInFirstRound = 0
    private(set) var firstRoundEntityKinds: [String] = []
    private(set) var receivedMessageIds: [String] = []
    private(set) var checkpointWhenReceived: [String: UInt64] = [:]
    private(set) var checkpoint: UInt64?
    private(set) var sentCompletion = false
    nonisolated let sentUpdates = DeviceSyncTestEventRecorder<UInt32>()
    private var closedRounds = 0

    init(
        resumeFrom resumePoint: UInt64?,
        acknowledges: Bool = true,
        confirmsCompletion: Bool = true,
        onFirstMessages: (@Sendable () async throws -> Void)? = nil
    ) {
        self.resumePoint = resumePoint
        self.acknowledges = acknowledges
        self.confirmsCompletion = confirmsCompletion
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
        sentUpdates.record(update.id)

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
            if confirmsCompletion {
                confirmCompletion()
            }
        default:
            break
        }
    }

    func requestFiles(requestId: UInt32) {
        let request = Chat.DeviceSyncFileMessage.AvailabilityRequest(requestId: requestId, files: [])
        fileContinuations.forEach { $0.yield(.availabilityRequest(request)) }
    }

    func confirmCompletion() {
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
            firstRoundEntityKinds += update.entities.map(\.logLabel)
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
