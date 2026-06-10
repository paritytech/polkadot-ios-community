import Foundation
import MessageExchangeKit
import Operation_iOS
import StructuredConcurrency

enum DeviceSyncSessionFailure: Error {
    case connectionFailed(Error)
    case reconnectRequested
    case disconnected
    case ackTimeout(UInt32)
    case sendFailed(Error)
}

typealias DeviceSyncEntityApplyOverride = @Sendable (Chat.DeviceSyncEntity, UInt64) async throws -> Void

actor DeviceSyncSession {
    static let defaultConnectTimeout: Duration = .seconds(45)
    static let defaultAckTimeout: Duration = .seconds(30)
    static let defaultDisconnectGracePeriod: Duration = .seconds(2)

    let peerStatementAccountId: Data

    private let transport: DeviceSyncMessageTransporting
    private let signaler: DeviceSyncPeerConnectionSignaler
    private let dataChannel: any DeviceSyncDataChanneling
    private let contactDataProviderFactory: ChatContactDataProviderMaking
    private let messageDataProviderFactory: ChatMessageDataProviderMaking
    private let messageExchangeModeProvider: any MessageExchangeModeProviding
    private let outgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryMaking
    private let lastSyncOfferIdRepositoryFactory: LastSyncOfferIdRepositoryMaking
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let incomingUpdateApplier: DeviceSyncIncomingUpdateApplier
    private let outgoingChangesCollector: DeviceSyncOutgoingChangesCollector
    private let logger: LoggerProtocol
    private let failureHandler: @Sendable (DeviceSyncSession, Data, DeviceSyncSessionFailure) async -> Void
    private let connectTimeout: Duration
    private let ackTimeout: Duration
    private let disconnectGracePeriod: Duration
    private let pushInitialUpdate: Bool
    private let reconnectOfferId: String?
    private let entityApplyOverride: DeviceSyncEntityApplyOverride?

    private var sessionTask: Task<Void, Never>?
    private var ackTimeoutTask: Task<Void, Never>?
    private var disconnectGraceTask: Task<Void, Never>?

    private var pendingUpdates = [UInt32: Chat.DeviceSyncUpdate]()
    private var outgoingCheckpoint: UInt64?
    private var isDataChannelConnected = false
    private var isPushInProgress = false
    private var needsDeferredPush = false
    private var isFailed = false

    init(
        peerStatementAccountId: Data,
        initialCheckpoint: UInt64?,
        transport: DeviceSyncMessageTransporting,
        signaler: DeviceSyncPeerConnectionSignaler,
        dataChannel: any DeviceSyncDataChanneling,
        remoteContactResolver: RemoteContactResolving,
        deviceRepositoryFactory: LocalDeviceRepositoryMaking,
        contactRepositoryFactory: ChatContactRepositoryMaking,
        chatRepositoryFactory: ChatRepositoryMaking,
        messageRepositoryFactory: ChatMessageRepositoryMaking,
        contactDataProviderFactory: ChatContactDataProviderMaking,
        messageDataProviderFactory: ChatMessageDataProviderMaking,
        removedChatRepositoryFactory: RemovedChatRepositoryMaking,
        messageExchangeModeProvider: MessageExchangeModeProviding,
        outgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryMaking,
        lastSyncOfferIdRepositoryFactory: LastSyncOfferIdRepositoryMaking = LastSyncOfferIdRepositoryFactory(),
        updateIdProvider: DeviceSyncUpdateIdProviding,
        logger: LoggerProtocol,
        connectTimeout: Duration = DeviceSyncSession.defaultConnectTimeout,
        ackTimeout: Duration = DeviceSyncSession.defaultAckTimeout,
        disconnectGracePeriod: Duration = DeviceSyncSession.defaultDisconnectGracePeriod,
        pushInitialUpdate: Bool,
        reconnectOfferId: String?,
        entityApplyOverride: DeviceSyncEntityApplyOverride?,
        failureHandler: @escaping @Sendable (DeviceSyncSession, Data, DeviceSyncSessionFailure) async -> Void
    ) {
        self.peerStatementAccountId = peerStatementAccountId
        outgoingCheckpoint = initialCheckpoint
        self.transport = transport
        self.signaler = signaler
        self.dataChannel = dataChannel
        self.contactDataProviderFactory = contactDataProviderFactory
        self.messageDataProviderFactory = messageDataProviderFactory
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.outgoingUpdateTimeRepositoryFactory = outgoingUpdateTimeRepositoryFactory
        self.lastSyncOfferIdRepositoryFactory = lastSyncOfferIdRepositoryFactory
        self.updateIdProvider = updateIdProvider
        incomingUpdateApplier = DeviceSyncIncomingUpdateApplier(
            remoteContactResolver: remoteContactResolver,
            contactRepositoryFactory: contactRepositoryFactory,
            chatRepositoryFactory: chatRepositoryFactory,
            messageRepositoryFactory: messageRepositoryFactory,
            removedChatRepositoryFactory: removedChatRepositoryFactory,
            logger: logger
        )
        outgoingChangesCollector = DeviceSyncOutgoingChangesCollector(
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: contactRepositoryFactory,
            messageRepositoryFactory: messageRepositoryFactory,
            removedChatRepositoryFactory: removedChatRepositoryFactory,
            messageExchangeModeProvider: messageExchangeModeProvider
        )
        self.logger = logger
        self.connectTimeout = connectTimeout
        self.ackTimeout = ackTimeout
        self.disconnectGracePeriod = disconnectGracePeriod
        self.pushInitialUpdate = pushInitialUpdate
        self.reconnectOfferId = reconnectOfferId
        self.entityApplyOverride = entityApplyOverride
        self.failureHandler = failureHandler
    }

    deinit {
        logger.debug("Deinit for \(peerStatementAccountId.toHex())")
    }

    func start() async {
        sessionTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self?.receiveUpdates() }
                group.addTask { await self?.receiveAcks() }
                group.addTask { await self?.observeLocalChanges() }
                group.addTask { await self?.observeDataChannelState() }
                group.addTask { await self?.observeReconnectSignals() }
                group.addTask { await self?.observeAcceptedOfferIds() }
            }
        }

        logger.debug("Starting signaler for \(peerStatementAccountId.toHex())")
        await signaler.startListening()

        if let reconnectOfferId {
            logger.debug("Sending Reconnected signal before data channel connect")
            await signaler.sendReconnected(offerId: reconnectOfferId)
        }

        logger.debug("Connecting data channel for \(peerStatementAccountId.toHex())")

        do {
            try await withTimeout(connectTimeout) { [dataChannel] in
                try await dataChannel.connect()
            }
        } catch {
            logger.error("Data channel connection failed: \(error)")
            await failSession(.connectionFailed(error))
            return
        }

        isDataChannelConnected = true
        logger.debug("Data channel connected with \(peerStatementAccountId.toHex())")

        if pushInitialUpdate {
            await requestPushUpdate()
        }
    }

    func close() async {
        sessionTask?.cancel()
        sessionTask = nil
        ackTimeoutTask?.cancel()
        ackTimeoutTask = nil
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil

        isDataChannelConnected = false
        isPushInProgress = false
        isFailed = true
        await dataChannel.close()
        await signaler.stopListening()
        await transport.close()
    }
}

// MARK: - Failure

extension DeviceSyncSession {
    private func failSession(_ failure: DeviceSyncSessionFailure) async {
        guard !isFailed else { return }

        logger.error("Device sync session failed for \(peerStatementAccountId.toHex()): \(failure)")

        isFailed = true
        isDataChannelConnected = false
        isPushInProgress = false

        sessionTask?.cancel()
        sessionTask = nil
        ackTimeoutTask?.cancel()
        ackTimeoutTask = nil
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil

        await dataChannel.close()
        await signaler.stopListening()
        await transport.close()

        await failureHandler(self, peerStatementAccountId, failure)
    }
}

// MARK: - Reconnect

extension DeviceSyncSession {
    private func observeReconnectSignals() async {
        do {
            for try await offerId in signaler.reconnects {
                guard !Task.isCancelled else { return }
                logger.debug(
                    "Reconnect requested by peer for \(peerStatementAccountId.toHex()), " +
                        "offerId=\(offerId), resetting session"
                )
                await persistLastSyncOfferId(nil)
                await failSession(.reconnectRequested)
                return
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Reconnect signal observation failed: \(error)")
        }
    }
}

// MARK: - Offer ID Persistence

extension DeviceSyncSession {
    private func observeAcceptedOfferIds() async {
        do {
            for try await offerId in signaler.acceptedOfferIds {
                guard !Task.isCancelled else { return }
                await persistLastSyncOfferId(offerId)
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Accepted offer id observation failed: \(error)")
        }
    }

    private func persistLastSyncOfferId(_ offerId: String?) async {
        let update = Chat.LastSyncOfferIdUpdate(
            statementAccountId: peerStatementAccountId,
            lastSyncOfferId: offerId
        )

        do {
            let repository = lastSyncOfferIdRepositoryFactory.createRepository(forFilter: nil)
            let operation = repository.saveOperation({ [update] }, { [] })
            try await operation.asyncExecute()
            logger
                .debug("Updated lastSyncOfferId \(String(describing: offerId))" +
                    " for \(peerStatementAccountId.toHex())")
        } catch {
            logger.error("Failed to persist lastSyncOfferId: \(error)")
        }
    }
}

// MARK: - Local Changes

extension DeviceSyncSession {
    private func observeDataChannelState() async {
        do {
            for try await state in dataChannel.states {
                guard !Task.isCancelled else { return }

                switch state {
                case .connected:
                    isDataChannelConnected = true
                    cancelDisconnectGrace()
                    await requestPushUpdate()
                case .disconnected:
                    isDataChannelConnected = false
                    startDisconnectGrace()
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Data channel state observation failed: \(error)")
            await failSession(.disconnected)
        }
    }

    private func startDisconnectGrace() {
        guard disconnectGraceTask == nil else { return }

        logger.warning(
            "Data channel disconnected for \(peerStatementAccountId.toHex()), waiting \(disconnectGracePeriod)"
        )

        disconnectGraceTask = Task { [weak self, disconnectGracePeriod] in
            do {
                try await Task.sleep(for: disconnectGracePeriod)
            } catch {
                return
            }

            await self?.handleDisconnectGraceExpired()
        }
    }

    private func cancelDisconnectGrace() {
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil
    }

    private func handleDisconnectGraceExpired() async {
        disconnectGraceTask = nil
        await failSession(.disconnected)
    }

    private func observeLocalChanges() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeContactChanges() }
            group.addTask { await self.observeMessageChanges() }
        }
    }

    private func observeContactChanges() async {
        do {
            for try await _ in contactDataProviderFactory.subscribeContactsWithPredicate(.acceptedContacts) {
                guard !Task.isCancelled else { return }
                await requestPushUpdate()
            }
        } catch {
            logger.error("Contact sync observation failed: \(error)")
        }
    }

    private func observeMessageChanges() async {
        let multideviceSignKeyIds = messageExchangeModeProvider.multideviceSignKeyIds

        guard !multideviceSignKeyIds.isEmpty else { return }

        do {
            for try await _ in messageDataProviderFactory.subscribeMessages(
                with: .syncableMessagesForAcceptedContacts(
                    since: nil,
                    ownSignKeyIds: multideviceSignKeyIds
                )
            ) {
                guard !Task.isCancelled else { return }
                await requestPushUpdate()
            }
        } catch {
            logger.error("Message sync observation failed: \(error)")
        }
    }
}

// MARK: - Receiving

extension DeviceSyncSession {
    private func receiveUpdates() async {
        do {
            for try await update in dataChannel.updates {
                guard !Task.isCancelled else { return }
                await processSyncUpdate(update)
            }
        } catch {
            logger.error("Update receive failed: \(error)")
        }
    }

    private func receiveAcks() async {
        do {
            for try await ack in dataChannel.acks {
                guard !Task.isCancelled else { return }
                await processSyncUpdateAck(ack)
            }
        } catch {
            logger.error("Ack receive failed: \(error)")
        }
    }
}

// MARK: - Incoming Updates

extension DeviceSyncSession {
    private func processSyncUpdate(_ update: Chat.DeviceSyncUpdate) async {
        do {
            for entity in update.entities {
                try await applyEntity(entity, updateTimePoint: update.timePoint)
            }
        } catch {
            logger.error("Failed to apply sync update id=\(update.id): \(error)")
            return
        }

        let ack = Chat.DeviceSyncUpdateAck(id: update.id)
        do {
            try await dataChannel.sendAck(ack)
            logger.debug("Sent SyncUpdateAck id=\(ack.id)")
        } catch {
            logger.error("Failed to send ack: \(error)")
            await failSession(.sendFailed(error))
        }
    }

    private func applyEntity(
        _ entity: Chat.DeviceSyncEntity,
        updateTimePoint: UInt64
    ) async throws {
        if let entityApplyOverride {
            try await entityApplyOverride(entity, updateTimePoint)
            return
        }
        try await incomingUpdateApplier.applyEntity(entity, updateTimePoint: updateTimePoint)
    }
}

// MARK: - Outgoing Updates

extension DeviceSyncSession {
    private func requestPushUpdate() async {
        guard isDataChannelConnected else {
            needsDeferredPush = true
            return
        }

        guard !isPushInProgress, pendingUpdates.isEmpty else {
            needsDeferredPush = true
            return
        }

        needsDeferredPush = false
        isPushInProgress = true
        await pushNextUpdate()
        isPushInProgress = false

        if pendingUpdates.isEmpty, needsDeferredPush {
            await requestPushUpdate()
        }
    }

    private func pushNextUpdate() async {
        let checkpoint = outgoingCheckpoint
        var sendingUpdateId: UInt32?

        do {
            let changes = try await outgoingChangesCollector.collectEntities(since: checkpoint)

            guard !changes.entities.isEmpty, let timePoint = changes.timePoint else {
                logger.debug("No pending updates to send")
                return
            }

            let updateId = updateIdProvider.nextId()

            let update = Chat.DeviceSyncUpdate(
                id: updateId,
                entities: changes.entities,
                timePoint: timePoint
            )

            pendingUpdates[updateId] = update
            sendingUpdateId = updateId

            try await dataChannel.sendUpdate(update)
            startAckTimeout(for: updateId)
            logger.debug(
                "Sent SyncUpdate id=\(updateId) groups=\(changes.entities.count) " +
                    "entities=\(changes.entities.syncLogSummary)"
            )
        } catch {
            if let failedUpdateId = sendingUpdateId {
                pendingUpdates.removeValue(forKey: failedUpdateId)
            }
            logger.error("Failed to send pending updates: \(error)")
            await failSession(.sendFailed(error))
        }
    }
}

// MARK: - Ack Processing

extension DeviceSyncSession {
    private func processSyncUpdateAck(_ ack: Chat.DeviceSyncUpdateAck) async {
        guard let update = pendingUpdates.removeValue(forKey: ack.id) else {
            logger.warning("Received ack for unknown update id=\(ack.id)")
            return
        }
        ackTimeoutTask?.cancel()
        ackTimeoutTask = nil

        logger.debug("Received SyncUpdateAck id=\(ack.id) entities=\(update.entities.syncLogSummary)")
        await advanceOutgoingUpdateTime(to: update.timePoint)

        if needsDeferredPush {
            await requestPushUpdate()
        }
    }

    private func startAckTimeout(for updateId: UInt32) {
        ackTimeoutTask?.cancel()
        let ackTimeout = ackTimeout
        ackTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: ackTimeout)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self?.handleAckTimeout(for: updateId)
        }
    }

    private func handleAckTimeout(for updateId: UInt32) async {
        guard pendingUpdates[updateId] != nil else {
            return
        }

        pendingUpdates.removeValue(forKey: updateId)
        await failSession(.ackTimeout(updateId))
    }

    private func advanceOutgoingUpdateTime(to timePoint: UInt64) async {
        outgoingCheckpoint = timePoint

        let update = Chat.OutgoingUpdateTimeUpdate(
            statementAccountId: peerStatementAccountId,
            outgoingUpdateTime: timePoint
        )

        do {
            let repository = outgoingUpdateTimeRepositoryFactory.createRepository(forFilter: nil)
            let operation = repository.saveOperation({ [update] }, { [] })
            try await operation.asyncExecute()
            logger.debug("Advanced outgoingUpdateTime to \(timePoint)")
        } catch {
            logger.error("Failed to advance outgoingUpdateTime: \(error)")
        }
    }
}

private extension [Chat.DeviceSyncEntity] {
    var syncLogSummary: String {
        map { entity in
            switch entity {
            case let .devices(devices):
                "devices:\(devices.count)"
            case let .chatsAdded(chatIds):
                "chatsAdded:\(chatIds.count)"
            case let .chatsRemoved(chatIds):
                "chatsRemoved:\(chatIds.count)"
            case let .messages(messages):
                "messages:\(messages.count)"
            }
        }.joined(separator: ";")
    }
}
