@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

struct DeviceSyncSessionRecoveryTests {
    // MARK: - Startup and Reconnect Recovery

    @Test("Connect failure notifies failure handler")
    func connectFailureNotifiesFailureHandler() async throws {
        let peerAccountId = Data(repeating: 1, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .failure(MockDeviceSyncError.connectFailed))
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder
        )

        await session.start()

        let recorded = await failureRecorder.recordedFailure
        #expect(recorded?.accountId == peerAccountId)

        guard case .connectionFailed = recorded?.failure else {
            Issue.record("Expected connectionFailed, got \(String(describing: recorded?.failure))")
            return
        }

        #expect(await dataChannel.didClose)
        #expect(transport.didClose)
    }

    @Test("Disconnected data channel state notifies failure handler")
    func disconnectedStateNotifiesFailureHandler() async throws {
        let peerAccountId = Data(repeating: 2, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            disconnectGracePeriod: .milliseconds(250),
            pushInitialUpdate: false
        )

        await session.start()
        await dataChannel.sendState(.disconnected)

        let recorded = try await failureRecorder.waitForRecordedFailure(timeout: .seconds(10))
        #expect(recorded?.accountId == peerAccountId)

        guard case .disconnected = recorded?.failure else {
            Issue.record("Expected disconnected, got \(String(describing: recorded?.failure))")
            return
        }

        #expect(await dataChannel.didClose)
        #expect(transport.didClose)
    }

    @Test("Reconnected signal send encodes reconnected content")
    func reconnectedSignalSendEncodesReconnectedContent() async throws {
        let transport = MockDeviceSyncMessageTransport()
        let signaler = DeviceSyncPeerConnectionSignaler(
            transport: transport,
            role: .acceptor,
            logger: MockLogger()
        )

        await signaler.sendReconnected(offerId: "offer-1")

        let sentMessage = try #require(transport.sentMessages.first)
        let decoder = try ScaleDecoder(data: sentMessage)
        let envelope = try Chat.DeviceSyncSignalingEnvelope(scaleDecoder: decoder)

        #expect(envelope.offerId == "offer-1")
        #expect(envelope.message == .reconnected)
    }

    @Test("Matching reconnected signal emits active offer id")
    func matchingReconnectedSignalEmitsActiveOfferId() async throws {
        let transport = MockDeviceSyncMessageTransport()
        let signaler = DeviceSyncPeerConnectionSignaler(
            transport: transport,
            role: .initiator,
            logger: MockLogger()
        )

        await signaler.startListening()
        try await transport.waitForMessageSubscriber(timeout: .seconds(10))

        _ = try await signaler.send(.offer(SdpCoderTests.validOfferSdp))

        let sentMessage = try #require(
            try await transport.waitForSentMessageCount(1, timeout: .seconds(10)).first
        )
        let sentDecoder = try ScaleDecoder(data: sentMessage)
        let sentEnvelope = try Chat.DeviceSyncSignalingEnvelope(scaleDecoder: sentDecoder)

        let reconnectedMessage = try Self.encodedSignalingEnvelope(
            offerId: sentEnvelope.offerId,
            message: .reconnected
        )
        transport.emitMessage(reconnectedMessage)

        let offerId = try await Self.waitForReconnect(
            from: signaler,
            timeout: .seconds(10)
        )

        #expect(offerId == sentEnvelope.offerId)

        await signaler.stopListening()
    }

    @Test("Session sends reconnect before waiting for data channel connection")
    func sessionSendsReconnectBeforeWaitingForDataChannelConnection() async throws {
        let peerAccountId = Data(repeating: 9, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()), suspendConnect: true)
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            pushInitialUpdate: false,
            reconnectOfferId: "offer-2"
        )

        let startTask = Task {
            await session.start()
        }

        let sentMessages = try await transport.waitForSentMessageCount(1, timeout: .seconds(10))
        let sentMessage = try #require(sentMessages.first)
        let decoder = try ScaleDecoder(data: sentMessage)
        let envelope = try Chat.DeviceSyncSignalingEnvelope(scaleDecoder: decoder)

        #expect(envelope.offerId == "offer-2")
        #expect(envelope.message == .reconnected)

        await session.close()
        startTask.cancel()
    }

    @Test("Reconnected without matching active offer is ignored")
    func reconnectedWithoutMatchingActiveOfferIsIgnored() async throws {
        let peerAccountId = Data(repeating: 7, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()), suspendConnect: true)
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            pushInitialUpdate: false
        )

        let startTask = Task {
            await session.start()
        }
        try await transport.waitForMessageSubscriber(timeout: .seconds(10))

        let reconnectedMessage = try Self.encodedSignalingEnvelope(
            offerId: "stale-offer",
            message: .reconnected
        )
        transport.emitMessage(reconnectedMessage)

        try await Task.sleep(for: .milliseconds(250))
        #expect(await failureRecorder.recordedFailure == nil)
        #expect(await !(dataChannel.didClose))
        #expect(!transport.didClose)

        await session.close()
        startTask.cancel()
    }

    private static func encodedSignalingEnvelope(
        offerId: String,
        message: Chat.DeviceSyncSignalingContent
    ) throws -> Data {
        let envelope = Chat.DeviceSyncSignalingEnvelope(offerId: offerId, message: message)
        let encoder = ScaleEncoder()
        try envelope.encode(scaleEncoder: encoder)
        return encoder.encode()
    }

    private static func waitForReconnect(
        from signaler: DeviceSyncPeerConnectionSignaler,
        timeout: Duration
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                for try await offerId in signaler.reconnects {
                    return offerId
                }

                return nil
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }

            let result = try await group.next()
            group.cancelAll()

            return result ?? nil
        }
    }

    // MARK: - Incoming Update Recovery

    @Test("Applied inbound update sends ack")
    func appliedInboundUpdateSendsAck() async throws {
        let peerAccountId = Data(repeating: 4, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            pushInitialUpdate: false
        )

        await session.start()

        let update = Chat.DeviceSyncUpdate(
            id: 42,
            entities: [.devices([])],
            timePoint: Date().toChatTimestamp()
        )
        await dataChannel.emitUpdate(update)

        let sentAck = try await dataChannel.waitForSentAck(timeout: .seconds(10))
        #expect(sentAck == Chat.DeviceSyncUpdateAck(id: 42))

        await session.close()
    }

    // MARK: - Outgoing Update Recovery

    @Test("Outgoing checkpoint advances only after ack")
    func outgoingCheckpointAdvancesOnlyAfterAck() async throws {
        let peerAccountId = Data(repeating: 13, count: 32)
        let createdAt = Date(timeIntervalSince1970: 2_345.678)
        let deviceRepositoryFactory = MockLocalDeviceRepositoryFactory()
        let outgoingUpdateTimeRepositoryFactory = MockOutgoingUpdateTimeRepositoryFactory()
        try await deviceRepositoryFactory.save([
            Chat.LocalDevice(
                statementAccountId: Data(repeating: 14, count: 32),
                encryptionPublicKey: Data(repeating: 15, count: 65),
                hostName: "acked-device",
                createdAt: createdAt,
                hostVersion: nil,
                osType: nil,
                osVersion: nil,
                outgoingUpdateTime: nil
            )
        ])

        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: MockChatContactRepositoryFactory(),
            messageRepositoryFactory: MockChatMessageRepositoryFactory(),
            removedChatRepositoryFactory: MockRemovedChatRepositoryFactory(),
            outgoingUpdateTimeRepositoryFactory: outgoingUpdateTimeRepositoryFactory
        )

        let startedAt = Date().toChatTimestamp()
        await session.start()
        let update = try await dataChannel.waitForSentUpdate(timeout: .seconds(10))
        let sentUpdate = try #require(update)
        let sentAt = Date().toChatTimestamp()

        #expect(sentUpdate.timePoint >= startedAt)
        #expect(sentUpdate.timePoint <= sentAt)
        #expect(outgoingUpdateTimeRepositoryFactory.savedUpdates.isEmpty)

        await dataChannel.emitAck(Chat.DeviceSyncUpdateAck(id: sentUpdate.id))
        let savedUpdate = try await outgoingUpdateTimeRepositoryFactory.waitForSavedUpdate(timeout: .seconds(10))

        #expect(savedUpdate?.statementAccountId == peerAccountId)
        #expect(savedUpdate?.outgoingUpdateTime == sentUpdate.timePoint)

        await session.close()
    }

    @Test("Ack timeout notifies failure handler")
    func ackTimeoutNotifiesFailureHandler() async throws {
        let peerAccountId = Data(repeating: 18, count: 32)
        let deviceRepositoryFactory = MockLocalDeviceRepositoryFactory()
        try await deviceRepositoryFactory.save([
            Chat.LocalDevice(
                statementAccountId: Data(repeating: 19, count: 32),
                encryptionPublicKey: Data(repeating: 20, count: 65),
                hostName: "timeout-device",
                createdAt: Date(timeIntervalSince1970: 4_567.89),
                hostVersion: nil,
                osType: nil,
                osVersion: nil,
                outgoingUpdateTime: nil
            )
        ])
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: MockChatContactRepositoryFactory(),
            messageRepositoryFactory: MockChatMessageRepositoryFactory(),
            removedChatRepositoryFactory: MockRemovedChatRepositoryFactory(),
            ackTimeout: .milliseconds(250)
        )

        await session.start()
        let update = try await dataChannel.waitForSentUpdate(timeout: .seconds(10))
        let sentUpdate = try #require(update)

        let recorded = try await failureRecorder.waitForRecordedFailure(timeout: .seconds(10))
        #expect(recorded?.accountId == peerAccountId)

        guard case let .ackTimeout(updateId) = recorded?.failure else {
            Issue.record("Expected ackTimeout, got \(String(describing: recorded?.failure))")
            return
        }

        #expect(updateId == sentUpdate.id)
        #expect(await dataChannel.didClose)
        #expect(transport.didClose)
    }

    @Test("Send update failure notifies failure handler")
    func sendUpdateFailureNotifiesFailureHandler() async throws {
        let peerAccountId = Data(repeating: 21, count: 32)
        let deviceRepositoryFactory = MockLocalDeviceRepositoryFactory()
        let outgoingUpdateTimeRepositoryFactory = MockOutgoingUpdateTimeRepositoryFactory()
        try await deviceRepositoryFactory.save([
            Chat.LocalDevice(
                statementAccountId: Data(repeating: 22, count: 32),
                encryptionPublicKey: Data(repeating: 23, count: 65),
                hostName: "send-failure-device",
                createdAt: Date(timeIntervalSince1970: 5_678.91),
                hostVersion: nil,
                osType: nil,
                osVersion: nil,
                outgoingUpdateTime: nil
            )
        ])
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(
            connectResult: .success(()),
            sendUpdateResult: .failure(MockDeviceSyncError.sendUpdateFailed)
        )
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: MockChatContactRepositoryFactory(),
            messageRepositoryFactory: MockChatMessageRepositoryFactory(),
            removedChatRepositoryFactory: MockRemovedChatRepositoryFactory(),
            outgoingUpdateTimeRepositoryFactory: outgoingUpdateTimeRepositoryFactory
        )

        await session.start()

        let recorded = try await failureRecorder.waitForRecordedFailure(timeout: .seconds(10))
        #expect(recorded?.accountId == peerAccountId)

        guard case .sendFailed = recorded?.failure else {
            Issue.record("Expected sendFailed, got \(String(describing: recorded?.failure))")
            return
        }

        #expect(outgoingUpdateTimeRepositoryFactory.savedUpdates.isEmpty)
        #expect(await dataChannel.didClose)
        #expect(transport.didClose)
    }

    @Test("Incoming messages are persisted and acked")
    func incomingMessagesArePersistedAndAcked() async throws {
        let peerAccountId = Data(repeating: 30, count: 32)
        let messageRepositoryFactory = MockChatMessageRepositoryFactory()
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))
        let localMessage = Chat.LocalMessage(
            messageId: "synced-message",
            chatId: .person(Data(repeating: 31, count: 32)),
            origin: .user,
            creationSource: .deviceSync,
            status: .outgoing(.sent),
            timestamp: 7_891,
            content: .text("hello"),
            reactions: []
        )
        let wireMessage = try #require(Chat.DeviceSyncWireMessage(from: localMessage))

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            messageRepositoryFactory: messageRepositoryFactory,
            pushInitialUpdate: false
        )

        await session.start()
        await dataChannel.emitUpdate(Chat.DeviceSyncUpdate(
            id: 45,
            entities: [.messages([wireMessage])],
            timePoint: 7_891
        ))

        let savedMessages = try await messageRepositoryFactory.waitForMessages(timeout: .seconds(10))
        let sentAck = try await dataChannel.waitForSentAck(timeout: .seconds(10))
        let savedMessage = try #require(savedMessages.first { $0.messageId == localMessage.messageId })
        #expect(savedMessage.creationSource == .deviceSync)
        #expect(sentAck == Chat.DeviceSyncUpdateAck(id: 45))

        await session.close()
    }

    @Test("Incoming synced message does not overwrite local device message")
    func incomingSyncedMessageDoesNotOverwriteLocalDeviceMessage() async throws {
        let peerAccountId = Data(repeating: 34, count: 32)
        let contactAccountId = Data(repeating: 35, count: 32)
        let messageRepositoryFactory = MockChatMessageRepositoryFactory()
        let existingMessage = Chat.LocalMessage(
            messageId: "local-device-message",
            chatId: .person(contactAccountId),
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(.new),
            timestamp: 9_001,
            content: .text("local content"),
            reactions: []
        )
        try await messageRepositoryFactory.save([existingMessage])

        let syncedMessage = Chat.LocalMessage(
            messageId: existingMessage.messageId,
            chatId: .person(contactAccountId),
            origin: .user,
            creationSource: .deviceSync,
            status: .outgoing(.delivered),
            timestamp: 9_002,
            content: .text("synced content"),
            reactions: []
        )
        let wireMessage = try #require(Chat.DeviceSyncWireMessage(from: syncedMessage))
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))
        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            messageRepositoryFactory: messageRepositoryFactory,
            pushInitialUpdate: false
        )

        await session.start()
        await dataChannel.emitUpdate(Chat.DeviceSyncUpdate(
            id: 47,
            entities: [.messages([wireMessage])],
            timePoint: 9_002
        ))

        let sentAck = try await dataChannel.waitForSentAck(timeout: .seconds(10))
        let savedMessage = try #require(
            try await messageRepositoryFactory.fetchMessages().first { $0.messageId == existingMessage.messageId }
        )

        #expect(sentAck == Chat.DeviceSyncUpdateAck(id: 47))
        #expect(savedMessage.creationSource == .localDevice)
        #expect(savedMessage.status == .outgoing(.new))
        #expect(savedMessage.content == .text("local content"))

        await session.close()
    }

    @Test("Incoming synced message overwrites device sync message")
    func incomingSyncedMessageOverwritesDeviceSyncMessage() async throws {
        let peerAccountId = Data(repeating: 36, count: 32)
        let contactAccountId = Data(repeating: 37, count: 32)
        let messageRepositoryFactory = MockChatMessageRepositoryFactory()
        let existingMessage = Chat.LocalMessage(
            messageId: "device-sync-message",
            chatId: .person(contactAccountId),
            origin: .user,
            creationSource: .deviceSync,
            status: .outgoing(.delivered),
            timestamp: 10_001,
            content: .text("old content"),
            reactions: []
        )
        try await messageRepositoryFactory.save([existingMessage])

        let syncedMessage = Chat.LocalMessage(
            messageId: existingMessage.messageId,
            chatId: .person(contactAccountId),
            origin: .user,
            creationSource: .deviceSync,
            status: .outgoing(.sent),
            timestamp: 10_002,
            content: .text("updated content"),
            reactions: []
        )
        let wireMessage = try #require(Chat.DeviceSyncWireMessage(from: syncedMessage))
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))
        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            messageRepositoryFactory: messageRepositoryFactory,
            pushInitialUpdate: false
        )

        await session.start()
        await dataChannel.emitUpdate(Chat.DeviceSyncUpdate(
            id: 48,
            entities: [.messages([wireMessage])],
            timePoint: 10_002
        ))

        let sentAck = try await dataChannel.waitForSentAck(timeout: .seconds(10))
        let savedMessage = try #require(
            try await messageRepositoryFactory.fetchMessages().first { $0.messageId == existingMessage.messageId }
        )

        #expect(sentAck == Chat.DeviceSyncUpdateAck(id: 48))
        #expect(savedMessage.creationSource == .deviceSync)
        #expect(savedMessage.status == .outgoing(.sent))
        #expect(savedMessage.content == .text("updated content"))

        await session.close()
    }

    @Test("Incoming removed chats delete contacts, store tombstones, and ack")
    func incomingRemovedChatsDeleteContactsStoreTombstonesAndAck() async throws {
        let peerAccountId = Data(repeating: 32, count: 32)
        let removedAccountId = Data(repeating: 33, count: 32)
        let updateTimePoint: UInt64 = 8_912
        let contactRepositoryFactory = MockChatContactRepositoryFactory()
        let removedChatRepositoryFactory = MockRemovedChatRepositoryFactory()
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(connectResult: .success(()))

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            contactRepositoryFactory: contactRepositoryFactory,
            removedChatRepositoryFactory: removedChatRepositoryFactory,
            pushInitialUpdate: false
        )

        await session.start()
        await dataChannel.emitUpdate(Chat.DeviceSyncUpdate(
            id: 46,
            entities: [.chatsRemoved([.contact(accountId: removedAccountId)])],
            timePoint: updateTimePoint
        ))

        let deletedIds = try await contactRepositoryFactory.waitForDeletedIds(timeout: .seconds(10))
        let tombstones = try await removedChatRepositoryFactory.waitForRemovedChats(timeout: .seconds(10))
        let sentAck = try await dataChannel.waitForSentAck(timeout: .seconds(10))

        #expect(deletedIds == [removedAccountId.toHex()])
        #expect(tombstones.contains {
            $0.accountId == removedAccountId &&
                $0.removedAt == Date.fromChatTimestamp(updateTimePoint)
        })
        #expect(sentAck == Chat.DeviceSyncUpdateAck(id: 46))

        await session.close()
    }

    @Test("Ack send failure notifies failure handler")
    func ackSendFailureNotifiesFailureHandler() async throws {
        let peerAccountId = Data(repeating: 6, count: 32)
        let transport = MockDeviceSyncMessageTransport()
        let dataChannel = MockDeviceSyncDataChannel(
            connectResult: .success(()),
            sendAckResult: .failure(MockDeviceSyncError.sendAckFailed)
        )
        let failureRecorder = DeviceSyncFailureRecorder()

        let session = makeSession(
            peerAccountId: peerAccountId,
            transport: transport,
            dataChannel: dataChannel,
            failureRecorder: failureRecorder,
            pushInitialUpdate: false
        )

        await session.start()

        let update = Chat.DeviceSyncUpdate(
            id: 44,
            entities: [.devices([])],
            timePoint: Date().toChatTimestamp()
        )
        await dataChannel.emitUpdate(update)

        let recorded = try await failureRecorder.waitForRecordedFailure(timeout: .seconds(10))
        #expect(recorded?.accountId == peerAccountId)

        guard case .sendFailed = recorded?.failure else {
            Issue.record("Expected sendFailed, got \(String(describing: recorded?.failure))")
            return
        }

        #expect(await dataChannel.didClose)
        #expect(transport.didClose)
    }
}
