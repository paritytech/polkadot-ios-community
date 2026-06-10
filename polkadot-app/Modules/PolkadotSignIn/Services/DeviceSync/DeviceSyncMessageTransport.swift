import Foundation
import Foundation_iOS
import CryptoKit
import SubstrateSdk
import StatementStore
import MessageExchangeKit
import AsyncExtensions
import StructuredConcurrency

// MARK: - Protocol

protocol DeviceSyncMessageTransporting {
    var messageBatches: AnyAsyncSequence<[Data]> { get }
    func open() async
    func close() async
    func send(_ data: Data) async
}

// MARK: - Implementation

/// Encrypted message transport between two devices over the statement store,
/// backed by the `MessageExchangeKit` infrastructure (`PeerSession`).
///
/// Used by `DeviceSyncPeerConnectionSignaler` to carry WebRTC signaling
/// messages for the device sync data channel.
final class DeviceSyncMessageTransport: TypeErasedDelegateStoring {
    private let serviceFactory: MessageExchangeServiceFactory
    private let connection: StatementStoreConnecting
    private let peer: MessageExchange.Peer
    private let ownSignKeyId: String
    private let ownEncryptionKeyId: String
    private let logger: LoggerProtocol

    private let state = DeviceSyncMessageTransportState()
    private let messageSubject = AsyncPassthroughSubject<[Data]>()

    init(
        connection: StatementStoreConnecting,
        signerManager: StatementStoreSignerManaging,
        encryptionManager: MessageExchangeEncryptionManaging,
        ownSignKeyId: String,
        ownEncryptionKeyId: String,
        peerStatementAccountId: Data,
        peerEncryptionPublicKey: Data,
        logger: LoggerProtocol
    ) {
        self.connection = connection
        self.ownSignKeyId = ownSignKeyId
        self.ownEncryptionKeyId = ownEncryptionKeyId
        self.logger = logger

        peer = MessageExchange.Peer(
            accountId: peerStatementAccountId,
            publicKey: peerEncryptionPublicKey,
            pin: nil,
            devices: []
        )

        serviceFactory = MessageExchangeServiceFactory(
            messageExchangeModeProvider: FixedMessageExchangeModeProvider(mode: .identity),
            signManager: signerManager,
            encryptionManager: encryptionManager,
            deviceEncryptionKeyFactory: nil,
            maxStatementSize: MessageExchangeCoordinatorFactory.Constants.maxDeviceSyncStatementSize,
            workQueue: DispatchQueue(label: "device.sync.transport.queue"),
            logger: logger
        )
    }

    deinit {
        logger.debug("Deinit")
    }
}

private actor DeviceSyncMessageTransportState {
    private var exchangeService: AnyMessageExchangeService<Data>?
    private var isClosed = false

    func installServiceIfOpen(_ service: AnyMessageExchangeService<Data>) -> Bool {
        guard !isClosed else { return false }
        exchangeService = service
        return true
    }

    func currentServiceIfOpen() -> AnyMessageExchangeService<Data>? {
        guard !isClosed else { return nil }
        return exchangeService
    }

    func close() {
        isClosed = true
        exchangeService = nil
    }
}

// MARK: - DeviceSyncMessageTransporting

extension DeviceSyncMessageTransport: DeviceSyncMessageTransporting {
    var messageBatches: AnyAsyncSequence<[Data]> {
        messageSubject.eraseToAnyAsyncSequence()
    }

    func open() async {
        do {
            let delegate = AnyPeerSessionDelegate<Data>(self)

            let service = try serviceFactory.makeService(
                statementStoreConnection: connection,
                delegate: delegate
            )

            let own = MessageExchange.Own(
                signKeyId: ownSignKeyId,
                encryptionKeyId: ownEncryptionKeyId,
                pin: nil
            )

            let request = MessageExchange.SessionRequest(own: own, peer: peer)
            guard await state.installServiceIfOpen(service) else { return }
            service.updateSessions([request])
        } catch {
            logger.error("Failed to create service: \(error)")
        }
    }

    func close() async {
        await state.close()
    }

    func send(_ data: Data) async {
        guard let service = await state.currentServiceIfOpen() else {
            logger.error("Cannot send - not open")
            return
        }
        service.addMessageToQueue(data, for: peer)
    }
}

// MARK: - PeerSessionDelegate

extension DeviceSyncMessageTransport: PeerSessionDelegate {
    typealias Message = Data

    func peerSession(
        _: any PeerSessionProtocol,
        didUpdateState state: PeerSessionState
    ) {
        logger.debug("Session state → \(state)")
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didInitializeWithOutgoingMessages _: [Data]
    ) {}

    func peerSession(
        _: any PeerSessionProtocol,
        shouldResetAfter _: MessageExchange.InitializationError
    ) -> Bool { true }

    func peerSession(
        _: any PeerSessionProtocol,
        didFinishAddingMessageToQueue _: Data,
        withError error: MessageExchange.AddToQueueError?
    ) {
        if let error {
            logger.error("Add to queue error: \(error)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didPostMessages messages: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        if let error {
            logger.error("Post error: \(error)")
        } else {
            logger.debug("Posted \(messages.count) message(s)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didDeliverMessages messages: [Data],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        if let error {
            logger.error("Delivery error: \(error)")
        } else {
            logger.debug("Delivered \(messages.count) message(s)")
        }
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didReceiveMessages messages: [Data],
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        logger.debug("Received \(messages.count) message(s)")

        messageSubject.send(messages)

        respondHandler(.success)
    }

    func peerSessionDidReceiveMessagesError(
        _: any PeerSessionProtocol,
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        logger.error("Received error, respond success")
        respondHandler(.success)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldIgnoreStatementAfter _: MessageExchange.IncomingMessageError
    ) -> Bool { true }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldReinitializeAfterSubmitError _: Error
    ) -> Bool { true }
}
