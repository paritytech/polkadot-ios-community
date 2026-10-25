import Foundation
import Foundation_iOS
import CryptoKit
import SubstrateSdk
import StatementStore
import MessageExchangeKit
import AsyncExtensions
import StructuredConcurrency

// MARK: - Protocol

protocol DeviceSyncMessageTransporting: Sendable {
    func open(delegate: AnyPeerSessionDelegate<Data>) async throws
    func close() async
    func send(_ messages: [Data]) async
}

// MARK: - Implementation

/// Encrypted message transport between two devices over the statement store,
/// backed by the `MessageExchangeKit` infrastructure (`PeerSession`).
///
/// Used by `DeviceSyncSignalingSession` to carry WebRTC signaling
/// messages for the device sync data channel.
final class DeviceSyncMessageTransport: @unchecked Sendable {
    private let serviceFactory: MessageExchageServiceMaking
    private let signerResolver: PeerSessionSignerResolving
    private let connection: StatementStoreConnecting
    private let sessionRequest: MessageExchange.SessionRequest
    private let peerLogger: LoggerProtocol

    private let state = DeviceSyncMessageTransportState()

    init(
        serviceFactory: MessageExchageServiceMaking,
        signerResolver: PeerSessionSignerResolving,
        connection: StatementStoreConnecting,
        sessionRequest: MessageExchange.SessionRequest,
        peerLogger: LoggerProtocol
    ) {
        self.serviceFactory = serviceFactory
        self.signerResolver = signerResolver
        self.connection = connection
        self.sessionRequest = sessionRequest
        self.peerLogger = peerLogger
    }

    convenience init(
        connection: StatementStoreConnecting,
        signerManager: StatementStoreSignerManaging,
        encryptionManager: MessageExchangeEncryptionManaging,
        ownSignKeyId: String,
        ownEncryptionKeyId: String,
        peerStatementAccountId: Data,
        peerEncryptionPublicKey: Data,
        peerLogger: LoggerProtocol
    ) {
        let serviceFactory = MessageExchangeServiceFactory(
            messageExchangeModeProvider: FixedMessageExchangeModeProvider(mode: .identity),
            signManager: signerManager,
            encryptionManager: encryptionManager,
            deviceEncryptionKeyFactory: nil,
            maxStatementSize: MessageExchangeCoordinatorFactory.Constants.maxDeviceSyncStatementSize,
            workQueue: DispatchQueue(label: "device.sync.transport.queue"),
            logger: peerLogger
        )

        self.init(
            serviceFactory: serviceFactory,
            signerResolver: IdentitySignerResolver(signManager: signerManager),
            connection: connection,
            sessionRequest: MessageExchange.SessionRequest(
                own: MessageExchange.Own(signKeyId: ownSignKeyId, encryptionKeyId: ownEncryptionKeyId, pin: nil),
                peer: MessageExchange.Peer(
                    accountId: peerStatementAccountId,
                    publicKey: peerEncryptionPublicKey,
                    pin: nil,
                    devices: []
                )
            ),
            peerLogger: peerLogger
        )
    }

    deinit {
        peerLogger.debug("Deinit")
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
    func open(delegate: AnyPeerSessionDelegate<Data>) async throws {
        let service = try serviceFactory.makeService(
            statementStoreConnection: connection,
            statementSignerResolver: signerResolver,
            delegate: delegate
        )

        guard await state.installServiceIfOpen(service) else {
            throw CancellationError()
        }
        service.updateSessions([sessionRequest])
    }

    func close() async {
        await state.close()
    }

    func send(_ messages: [Data]) async {
        guard !messages.isEmpty else {
            return
        }

        guard let service = await state.currentServiceIfOpen() else {
            peerLogger.error("Cannot send - not open")
            return
        }

        service.addMessagesToQueue(messages, for: sessionRequest.peer)
    }
}
