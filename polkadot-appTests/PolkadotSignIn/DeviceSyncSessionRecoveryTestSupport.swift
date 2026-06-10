@testable import polkadot_app
import AsyncExtensions
import Foundation
import Operation_iOS
import SubstrateSdk

extension DeviceSyncSessionRecoveryTests {
    func makeSession(
        peerAccountId: Data,
        transport: MockDeviceSyncMessageTransport,
        dataChannel: MockDeviceSyncDataChannel,
        failureRecorder: DeviceSyncFailureRecorder? = nil,
        deviceRepositoryFactory: LocalDeviceRepositoryMaking = MockLocalDeviceRepositoryFactory(),
        contactRepositoryFactory: ChatContactRepositoryMaking = MockChatContactRepositoryFactory(),
        messageRepositoryFactory: ChatMessageRepositoryMaking = MockChatMessageRepositoryFactory(),
        removedChatRepositoryFactory: RemovedChatRepositoryMaking = MockRemovedChatRepositoryFactory(),
        outgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryMaking =
            MockOutgoingUpdateTimeRepositoryFactory(),
        lastSyncOfferIdRepositoryFactory: LastSyncOfferIdRepositoryMaking = MockLastSyncOfferIdRepositoryFactory(),
        ackTimeout: Duration = .seconds(1),
        disconnectGracePeriod: Duration = DeviceSyncSession.defaultDisconnectGracePeriod,
        pushInitialUpdate: Bool = true,
        reconnectOfferId: String? = nil,
        role: CallRole = .acceptor
    ) -> DeviceSyncSession {
        let signaler = DeviceSyncPeerConnectionSignaler(
            transport: transport,
            role: role,
            logger: MockLogger()
        )
        let messageExchangeModeProvider = ChatMessageExchangeModeProvider()

        return DeviceSyncSession(
            peerStatementAccountId: peerAccountId,
            initialCheckpoint: nil,
            transport: transport,
            signaler: signaler,
            dataChannel: dataChannel,
            remoteContactResolver: MockRemoteContactResolver(result: .success(nil)),
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: contactRepositoryFactory,
            chatRepositoryFactory: MockChatRepositoryFactory(),
            messageRepositoryFactory: messageRepositoryFactory,
            contactDataProviderFactory: MockChatContactDataProviderFactory(),
            messageDataProviderFactory: MockChatMessageDataProviderFactory(),
            removedChatRepositoryFactory: removedChatRepositoryFactory,
            messageExchangeModeProvider: messageExchangeModeProvider,
            outgoingUpdateTimeRepositoryFactory: outgoingUpdateTimeRepositoryFactory,
            lastSyncOfferIdRepositoryFactory: lastSyncOfferIdRepositoryFactory,
            updateIdProvider: MockDeviceSyncUpdateIdProvider(),
            logger: MockLogger(),
            connectTimeout: .seconds(1),
            ackTimeout: ackTimeout,
            disconnectGracePeriod: disconnectGracePeriod,
            pushInitialUpdate: pushInitialUpdate,
            reconnectOfferId: reconnectOfferId,
            entityApplyOverride: nil,
            failureHandler: { _, accountId, failure in
                await failureRecorder?.record(accountId: accountId, failure: failure)
            }
        )
    }
}

enum MockDeviceSyncError: Error {
    case connectFailed
    case connectCancelled
    case sendUpdateFailed
    case sendAckFailed
}

struct MockRemoteContactResolver: RemoteContactResolving {
    let result: Result<Chat.RemoteContact?, Error>

    func fetch(by _: AccountId) async throws -> Chat.RemoteContact? {
        try result.get()
    }
}

final class MockDeviceSyncUpdateIdProvider: DeviceSyncUpdateIdProviding {
    private let lock = NSLock()
    private var next: UInt32

    init(startingAt next: UInt32 = 1) {
        self.next = next
    }

    func nextId() -> UInt32 {
        lock.withLock {
            let id = next
            next += 1
            return id
        }
    }
}

final class MockDeviceSyncMessageTransport: DeviceSyncMessageTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _didClose = false
    private var messageContinuations = [AsyncStream<[Data]>.Continuation]()
    private var pendingMessageBatches = [[Data]]()
    private var _sentMessages = [Data]()

    var messageBatches: AnyAsyncSequence<[Data]> {
        AsyncStream<[Data]> { continuation in
            lock.withLock {
                messageContinuations.append(continuation)
                pendingMessageBatches.forEach { continuation.yield($0) }
                pendingMessageBatches.removeAll()
            }
        }.eraseToAnyAsyncSequence()
    }

    var didClose: Bool {
        lock.withLock { _didClose }
    }

    var sentMessages: [Data] {
        lock.withLock { _sentMessages }
    }

    func open() async {}

    func close() async {
        lock.withLock { _didClose = true }
    }

    func send(_ data: Data) async {
        lock.withLock { _sentMessages.append(data) }
    }

    func waitForSentMessageCount(
        _ count: Int,
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> [Data] {
        let deadline = ContinuousClock.now + timeout

        while lock.withLock({ _sentMessages.count < count }), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return sentMessages
    }

    func emitMessage(_ data: Data) {
        emitMessageBatch([data])
    }

    func emitMessageBatch(_ batch: [Data]) {
        lock.withLock {
            guard !messageContinuations.isEmpty else {
                pendingMessageBatches.append(batch)
                return
            }

            messageContinuations.forEach { $0.yield(batch) }
        }
    }

    func waitForMessageSubscriber(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while lock.withLock({ messageContinuations.isEmpty }), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }
}

actor MockDeviceSyncDataChannel: DeviceSyncDataChanneling {
    private let connectResult: Result<Void, Error>
    private let sendUpdateResult: Result<Void, Error>
    private let sendAckResult: Result<Void, Error>
    private let suspendConnect: Bool
    private(set) var didClose = false
    private(set) var sentAcks = [Chat.DeviceSyncUpdateAck]()
    private(set) var sentUpdates = [Chat.DeviceSyncUpdate]()
    private var stateContinuations = [AsyncStream<DeviceSyncDataChannelState>.Continuation]()
    private var updateContinuations = [AsyncStream<Chat.DeviceSyncUpdate>.Continuation]()
    private var ackContinuations = [AsyncStream<Chat.DeviceSyncUpdateAck>.Continuation]()
    private var pendingStates = [DeviceSyncDataChannelState]()
    private var pendingUpdates = [Chat.DeviceSyncUpdate]()
    private var pendingAcks = [Chat.DeviceSyncUpdateAck]()
    private var connectContinuation: CheckedContinuation<Void, Error>?

    init(
        connectResult: Result<Void, Error>,
        sendUpdateResult: Result<Void, Error> = .success(()),
        sendAckResult: Result<Void, Error> = .success(()),
        suspendConnect: Bool = false
    ) {
        self.connectResult = connectResult
        self.sendUpdateResult = sendUpdateResult
        self.sendAckResult = sendAckResult
        self.suspendConnect = suspendConnect
    }

    nonisolated var updates: AnyAsyncSequence<Chat.DeviceSyncUpdate> {
        AsyncStream<Chat.DeviceSyncUpdate> { continuation in
            Task {
                await self.addUpdateContinuation(continuation)
            }
        }.eraseToAnyAsyncSequence()
    }

    nonisolated var acks: AnyAsyncSequence<Chat.DeviceSyncUpdateAck> {
        AsyncStream<Chat.DeviceSyncUpdateAck> { continuation in
            Task {
                await self.addAckContinuation(continuation)
            }
        }.eraseToAnyAsyncSequence()
    }

    nonisolated var states: AnyAsyncSequence<DeviceSyncDataChannelState> {
        AsyncStream<DeviceSyncDataChannelState> { continuation in
            Task {
                await self.addStateContinuation(continuation)
            }
        }.eraseToAnyAsyncSequence()
    }

    func connect() async throws {
        try connectResult.get()

        guard suspendConnect else { return }

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
        }
    }

    func sendUpdate(_ update: Chat.DeviceSyncUpdate) async throws {
        try sendUpdateResult.get()
        sentUpdates.append(update)
    }

    func sendAck(_ ack: Chat.DeviceSyncUpdateAck) async throws {
        try sendAckResult.get()
        sentAcks.append(ack)
    }

    func close() async {
        didClose = true
        connectContinuation?.resume(throwing: MockDeviceSyncError.connectCancelled)
        connectContinuation = nil
    }

    func waitForSentUpdate(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> Chat.DeviceSyncUpdate? {
        let deadline = ContinuousClock.now + timeout

        while sentUpdates.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return sentUpdates.first
    }

    func waitForSentAck(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> Chat.DeviceSyncUpdateAck? {
        let deadline = ContinuousClock.now + timeout

        while sentAcks.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return sentAcks.first
    }

    func sendState(_ state: DeviceSyncDataChannelState) {
        guard !stateContinuations.isEmpty else {
            pendingStates.append(state)
            return
        }

        stateContinuations.forEach { $0.yield(state) }
    }

    func emitUpdate(_ update: Chat.DeviceSyncUpdate) {
        guard !updateContinuations.isEmpty else {
            pendingUpdates.append(update)
            return
        }

        updateContinuations.forEach { $0.yield(update) }
    }

    func emitAck(_ ack: Chat.DeviceSyncUpdateAck) {
        guard !ackContinuations.isEmpty else {
            pendingAcks.append(ack)
            return
        }

        ackContinuations.forEach { $0.yield(ack) }
    }

    private func addStateContinuation(_ continuation: AsyncStream<DeviceSyncDataChannelState>.Continuation) {
        stateContinuations.append(continuation)
        pendingStates.forEach { continuation.yield($0) }
        pendingStates.removeAll()
    }

    private func addUpdateContinuation(_ continuation: AsyncStream<Chat.DeviceSyncUpdate>.Continuation) {
        updateContinuations.append(continuation)
        pendingUpdates.forEach { continuation.yield($0) }
        pendingUpdates.removeAll()
    }

    private func addAckContinuation(_ continuation: AsyncStream<Chat.DeviceSyncUpdateAck>.Continuation) {
        ackContinuations.append(continuation)
        pendingAcks.forEach { continuation.yield($0) }
        pendingAcks.removeAll()
    }
}

final class MockLocalDeviceRepositoryFactory: LocalDeviceRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.LocalDevice>()

    var databaseService: CoreDataServiceProtocol {
        fatalError("Core Data is not available in DeviceSyncSessionRecoveryTests mocks")
    }

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.LocalDevice> {
        AnyDataProviderRepository(repository)
    }

    func save(_ devices: [Chat.LocalDevice]) async throws {
        try await repository.saveOperation({ devices }, { [] }).asyncExecute()
    }
}

final class MockChatContactRepositoryFactory: ChatContactRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.Contact>()
    private let lock = NSLock()
    private var _deletedIds = [String]()

    var databaseService: CoreDataServiceProtocol {
        fatalError("Core Data is not available in DeviceSyncSessionRecoveryTests mocks")
    }

    var deletedIds: [String] {
        lock.withLock { _deletedIds }
    }

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.Contact> {
        AnyDataProviderRepository(MockChatContactRepository(
            repository: repository,
            onDelete: { [weak self] ids in
                self?.lock.withLock { self?._deletedIds.append(contentsOf: ids) }
            }
        ))
    }

    func waitForDeletedIds(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> [String] {
        let deadline = ContinuousClock.now + timeout

        while deletedIds.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return deletedIds
    }
}

final class MockChatContactRepository: DataProviderRepositoryProtocol {
    typealias Model = Chat.Contact

    private let repository: InMemoryDataProviderRepository<Chat.Contact>
    private let onDelete: ([String]) -> Void

    init(
        repository: InMemoryDataProviderRepository<Chat.Contact>,
        onDelete: @escaping ([String]) -> Void
    ) {
        self.repository = repository
        self.onDelete = onDelete
    }

    func fetchOperation(
        by modelIdClosure: @escaping () throws -> String,
        options: RepositoryFetchOptions
    ) -> BaseOperation<Chat.Contact?> {
        repository.fetchOperation(by: modelIdClosure, options: options)
    }

    func fetchAllOperation(with options: RepositoryFetchOptions) -> BaseOperation<[Chat.Contact]> {
        repository.fetchAllOperation(with: options)
    }

    func fetchOperation(
        by request: RepositorySliceRequest,
        options: RepositoryFetchOptions
    ) -> BaseOperation<[Chat.Contact]> {
        repository.fetchOperation(by: request, options: options)
    }

    func saveOperation(
        _ updateModelsBlock: @escaping () throws -> [Chat.Contact],
        _ deleteIdsBlock: @escaping () throws -> [String]
    ) -> BaseOperation<Void> {
        repository.saveOperation(updateModelsBlock) {
            let ids = try deleteIdsBlock()
            self.onDelete(ids)
            return ids
        }
    }

    func replaceOperation(
        _ newModelsBlock: @escaping () throws -> [Chat.Contact]
    ) -> BaseOperation<Void> {
        repository.replaceOperation(newModelsBlock)
    }

    func fetchCountOperation() -> BaseOperation<Int> {
        repository.fetchCountOperation()
    }

    func deleteAllOperation() -> BaseOperation<Void> {
        repository.deleteAllOperation()
    }
}

final class MockChatRepositoryFactory: ChatRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.LocalModel>()

    var databaseService: CoreDataServiceProtocol {
        fatalError("Core Data is not available in DeviceSyncSessionRecoveryTests mocks")
    }

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.LocalModel> {
        AnyDataProviderRepository(repository)
    }
}

final class MockChatMessageRepositoryFactory: ChatMessageRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.LocalMessage>()

    var databaseService: CoreDataServiceProtocol {
        fatalError("Core Data is not available in DeviceSyncSessionRecoveryTests mocks")
    }

    func createRepository(forFilter filter: NSPredicate?) -> AnyDataProviderRepository<Chat.LocalMessage> {
        createRepository(forFilter: filter, sortDescriptors: [])
    }

    func createRepository(
        forFilter _: NSPredicate?,
        sortDescriptors _: [NSSortDescriptor]
    ) -> AnyDataProviderRepository<Chat.LocalMessage> {
        AnyDataProviderRepository(repository)
    }

    func waitForMessages(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> [Chat.LocalMessage] {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            let messages = try await fetchMessages()
            if !messages.isEmpty {
                return messages
            }

            try await Task.sleep(for: pollInterval)
        }

        return try await fetchMessages()
    }

    func fetchMessages() async throws -> [Chat.LocalMessage] {
        try await repository.fetchAllOperation(with: .init()).asyncExecute()
    }

    func save(_ messages: [Chat.LocalMessage]) async throws {
        try await repository.saveOperation({ messages }, { [] }).asyncExecute()
    }
}

final class MockRemovedChatRepositoryFactory: RemovedChatRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.RemovedChat>()

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.RemovedChat> {
        AnyDataProviderRepository(repository)
    }

    func waitForRemovedChats(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> [Chat.RemovedChat] {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            let removedChats = try await repository.fetchAllOperation(with: .init()).asyncExecute()
            if !removedChats.isEmpty {
                return removedChats
            }

            try await Task.sleep(for: pollInterval)
        }

        return try await repository.fetchAllOperation(with: .init()).asyncExecute()
    }
}

final class MockChatContactDataProviderFactory: ChatContactDataProviderMaking {
    func createAllContactsProvider() -> StreamableProvider<Chat.Contact> {
        fatalError("Not used in DeviceSyncSessionRecoveryTests")
    }

    func subscribeContactsSnapshot(
        for _: NSPredicate?,
        deliverOn _: DispatchQueue,
        update _: @escaping ([Chat.Contact]) -> Void,
        failure _: @escaping (Error) -> Void
    ) -> AnyObject {
        MockSnapshotSubscription()
    }

    func subscribeChatsSnapshot(
        for _: NSPredicate?,
        deliverOn _: DispatchQueue,
        update _: @escaping ([Chat.LocalModel]) -> Void,
        failure _: @escaping (Error) -> Void
    ) -> AnyObject {
        MockSnapshotSubscription()
    }
}

final class MockChatMessageDataProviderFactory: ChatMessageDataProviderMaking {
    func createNewRemoteMessagesLifecycleProvider() -> StreamableProvider<Chat.LocalMessage> {
        fatalError("Not used in DeviceSyncSessionRecoveryTests")
    }

    func subscribeMessagesSnapshot(
        with _: NSPredicate?,
        deliverOn _: DispatchQueue,
        update _: @escaping ([Chat.LocalMessage]) -> Void
    ) -> AnyObject {
        MockSnapshotSubscription()
    }
}

final class MockSnapshotSubscription {}

final class MockOutgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.OutgoingUpdateTimeUpdate>()
    private let lock = NSLock()
    private var _savedUpdates = [Chat.OutgoingUpdateTimeUpdate]()

    var savedUpdates: [Chat.OutgoingUpdateTimeUpdate] {
        lock.withLock { _savedUpdates }
    }

    func waitForSavedUpdate(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> Chat.OutgoingUpdateTimeUpdate? {
        let deadline = ContinuousClock.now + timeout

        while savedUpdates.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return savedUpdates.first
    }

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.OutgoingUpdateTimeUpdate> {
        AnyDataProviderRepository(MockOutgoingUpdateTimeRepository(
            repository: repository,
            onSave: { [weak self] updates in
                self?.lock.withLock { self?._savedUpdates.append(contentsOf: updates) }
            }
        ))
    }
}

final class MockLastSyncOfferIdRepositoryFactory: LastSyncOfferIdRepositoryMaking {
    private let repository = InMemoryDataProviderRepository<Chat.LastSyncOfferIdUpdate>()
    private let lock = NSLock()
    private var _savedUpdates = [Chat.LastSyncOfferIdUpdate]()

    var savedUpdates: [Chat.LastSyncOfferIdUpdate] {
        lock.withLock { _savedUpdates }
    }

    func waitForSavedUpdate(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> Chat.LastSyncOfferIdUpdate? {
        let deadline = ContinuousClock.now + timeout

        while savedUpdates.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return savedUpdates.first
    }

    func createRepository(forFilter _: NSPredicate?) -> AnyDataProviderRepository<Chat.LastSyncOfferIdUpdate> {
        AnyDataProviderRepository(MockLastSyncOfferIdRepository(
            repository: repository,
            onSave: { [weak self] updates in
                self?.lock.withLock { self?._savedUpdates.append(contentsOf: updates) }
            }
        ))
    }
}

final class MockLastSyncOfferIdRepository: DataProviderRepositoryProtocol {
    typealias Model = Chat.LastSyncOfferIdUpdate

    private let repository: InMemoryDataProviderRepository<Chat.LastSyncOfferIdUpdate>
    private let onSave: ([Chat.LastSyncOfferIdUpdate]) -> Void

    init(
        repository: InMemoryDataProviderRepository<Chat.LastSyncOfferIdUpdate>,
        onSave: @escaping ([Chat.LastSyncOfferIdUpdate]) -> Void
    ) {
        self.repository = repository
        self.onSave = onSave
    }

    func fetchOperation(
        by modelIdClosure: @escaping () throws -> String,
        options: RepositoryFetchOptions
    ) -> BaseOperation<Chat.LastSyncOfferIdUpdate?> {
        repository.fetchOperation(by: modelIdClosure, options: options)
    }

    func fetchAllOperation(with options: RepositoryFetchOptions) -> BaseOperation<[Chat.LastSyncOfferIdUpdate]> {
        repository.fetchAllOperation(with: options)
    }

    func fetchOperation(
        by request: RepositorySliceRequest,
        options: RepositoryFetchOptions
    ) -> BaseOperation<[Chat.LastSyncOfferIdUpdate]> {
        repository.fetchOperation(by: request, options: options)
    }

    func saveOperation(
        _ updateModelsBlock: @escaping () throws -> [Chat.LastSyncOfferIdUpdate],
        _ deleteIdsBlock: @escaping () throws -> [String]
    ) -> BaseOperation<Void> {
        repository.saveOperation({
            let updates = try updateModelsBlock()
            self.onSave(updates)
            return updates
        }, deleteIdsBlock)
    }

    func replaceOperation(
        _ newModelsBlock: @escaping () throws -> [Chat.LastSyncOfferIdUpdate]
    ) -> BaseOperation<Void> {
        repository.replaceOperation(newModelsBlock)
    }

    func fetchCountOperation() -> BaseOperation<Int> {
        repository.fetchCountOperation()
    }

    func deleteAllOperation() -> BaseOperation<Void> {
        repository.deleteAllOperation()
    }
}

final class MockOutgoingUpdateTimeRepository: DataProviderRepositoryProtocol {
    typealias Model = Chat.OutgoingUpdateTimeUpdate

    private let repository: InMemoryDataProviderRepository<Chat.OutgoingUpdateTimeUpdate>
    private let onSave: ([Chat.OutgoingUpdateTimeUpdate]) -> Void

    init(
        repository: InMemoryDataProviderRepository<Chat.OutgoingUpdateTimeUpdate>,
        onSave: @escaping ([Chat.OutgoingUpdateTimeUpdate]) -> Void
    ) {
        self.repository = repository
        self.onSave = onSave
    }

    func fetchOperation(
        by modelIdClosure: @escaping () throws -> String,
        options: RepositoryFetchOptions
    ) -> BaseOperation<Chat.OutgoingUpdateTimeUpdate?> {
        repository.fetchOperation(by: modelIdClosure, options: options)
    }

    func fetchAllOperation(with options: RepositoryFetchOptions) -> BaseOperation<[Chat.OutgoingUpdateTimeUpdate]> {
        repository.fetchAllOperation(with: options)
    }

    func fetchOperation(
        by request: RepositorySliceRequest,
        options: RepositoryFetchOptions
    ) -> BaseOperation<[Chat.OutgoingUpdateTimeUpdate]> {
        repository.fetchOperation(by: request, options: options)
    }

    func saveOperation(
        _ updateModelsBlock: @escaping () throws -> [Chat.OutgoingUpdateTimeUpdate],
        _ deleteIdsBlock: @escaping () throws -> [String]
    ) -> BaseOperation<Void> {
        repository.saveOperation({
            let updates = try updateModelsBlock()
            self.onSave(updates)
            return updates
        }, deleteIdsBlock)
    }

    func replaceOperation(
        _ newModelsBlock: @escaping () throws -> [Chat.OutgoingUpdateTimeUpdate]
    ) -> BaseOperation<Void> {
        repository.replaceOperation(newModelsBlock)
    }

    func fetchCountOperation() -> BaseOperation<Int> {
        repository.fetchCountOperation()
    }

    func deleteAllOperation() -> BaseOperation<Void> {
        repository.deleteAllOperation()
    }
}

actor DeviceSyncFailureRecorder {
    private(set) var recordedFailure: (accountId: Data, failure: DeviceSyncSessionFailure)?

    func record(accountId: Data, failure: DeviceSyncSessionFailure) {
        recordedFailure = (accountId, failure)
    }

    func waitForRecordedFailure(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10)
    ) async throws -> (accountId: Data, failure: DeviceSyncSessionFailure)? {
        let deadline = ContinuousClock.now + timeout

        while recordedFailure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }

        return recordedFailure
    }
}
