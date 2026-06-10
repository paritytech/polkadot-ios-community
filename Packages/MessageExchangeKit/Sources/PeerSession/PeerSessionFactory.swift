import Foundation
import CryptoKit
import StatementStore
import SDKLogger
import SubstrateSdk

enum PeerSessionFactoryError: Error {
    case deviceEncryptionKeyFactoryMissing
}

public final class PeerSessionFactory<M: MessageExchange.CodableMessage> {
    public typealias Message = M

    private weak var delegate: AnyPeerSessionDelegate<M>?
    private let workQueue: DispatchQueue
    private let submitter: StatementStoreSubmitting
    private let signerManager: StatementStoreSignerManaging
    private let encryptionManager: MessageExchangeEncryptionManaging
    private let deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?
    private let messageExchangeModeProvider: MessageExchangeModeProviding
    private let sessionIdFactory: PeerSessionIdFactoryProtocol
    private let channelFactory: StatementChannelMaking
    private let preSendHandler: AnyPeerSessionPreSendHandler<M>
    private let pollerFactory: StatementSubscriptionFactoryProtocol
    private let maxStatementSize: Int
    private let operationQueue: OperationQueue
    private let logger: SDKLoggerProtocol?

    public init(
        delegate: AnyPeerSessionDelegate<M>,
        workQueue: DispatchQueue,
        submitter: StatementStoreSubmitting,
        encryptionManager: MessageExchangeEncryptionManaging,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking?,
        messageExchangeModeProvider: MessageExchangeModeProviding,
        signerManager: StatementStoreSignerManaging,
        sessionIdFactory: PeerSessionIdFactoryProtocol,
        channelFactory: StatementChannelMaking,
        preSendHandler: AnyPeerSessionPreSendHandler<M>,
        pollerFactory: StatementSubscriptionFactoryProtocol,
        maxStatementSize: Int,
        operationQueue: OperationQueue,
        logger: SDKLoggerProtocol?
    ) {
        self.delegate = delegate
        self.workQueue = workQueue
        self.submitter = submitter
        self.encryptionManager = encryptionManager
        self.deviceEncryptionKeyFactory = deviceEncryptionKeyFactory
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.signerManager = signerManager
        self.sessionIdFactory = sessionIdFactory
        self.channelFactory = channelFactory
        self.preSendHandler = preSendHandler
        self.pollerFactory = pollerFactory
        self.maxStatementSize = maxStatementSize
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension PeerSessionFactory: PeerSessionMaking {
    public func makeSession(
        for request: MessageExchange.SessionRequest
    ) -> AnyPeerSession<M>? {
        do {
            let signer = try signerManager.makeSigner(for: request.own.signKeyId)

            let identityEncryptionKeyFactory = try encryptionManager
                .makeEncryptorFactory(ownEncryptionKeyId: request.own.encryptionKeyId)

            let identityEncryptor = try identityEncryptionKeyFactory
                .makeEncryptor(remotePublicKey: request.peer.publicKey)

            let messageExchangeMode = messageExchangeModeProvider.mode(for: request.own)

            let outgoingSharedSecret = try deriveOutgoingSharedSecret(
                for: request,
                messageExchangeMode: messageExchangeMode,
                identitySharedSecret: identityEncryptor.sharedSecret
            )

            let sessionId = try sessionIdFactory.createSessionId(
                for: .init(
                    ownAccountId: signer.accountId,
                    ownPin: request.own.pin,
                    peerAccountId: request.peer.accountId,
                    peerPin: request.peer.pin,
                    sharedSecret: outgoingSharedSecret
                )
            )

            let priorityProvider = PeerSessionPriorityProvider(
                logger: logger
            )

            let statementDataCoder = try makeStatementDataCoder(
                for: request,
                messageExchangeMode: messageExchangeMode,
                identityEncryptor: identityEncryptor,
                identityEncryptionKeyFactory: identityEncryptionKeyFactory,
                signer: signer
            )

            let outgoingChannel = try makeOutgoingChannel(
                sessionId: sessionId,
                signer: signer,
                priorityProvider: priorityProvider,
                requestQueue: AnyOutgoingRequestQueue(OutgoingRequestQueue(
                    statementDataCoder: statementDataCoder,
                    sizeValidator: OutgoingRequestSizeValidator(maxStatementSize: maxStatementSize),
                    logger: logger
                ))
            )

            let incomingChannel = try makeIncomingChannel(
                sessionId: sessionId,
                signer: signer,
                priorityProvider: priorityProvider,
                statementDataCoder: statementDataCoder
            )

            let ownPoller = try pollerFactory.createSubscription(for: .init(
                accountId: signer.accountId,
                rawSessionId: sessionId.own
            ))

            let peerSubscription = try makePeerSubscription(
                for: request,
                messageExchangeMode: messageExchangeMode,
                identitySharedSecret: identityEncryptor.sharedSecret,
                identityEncryptionKeyFactory: identityEncryptionKeyFactory,
                signer: signer
            )

            let sessionInitializer = PeerSessionInitializer<Message>(
                priorityProvider: priorityProvider,
                ownPoller: ownPoller,
                peerSubscription: peerSubscription,
                workQueue: workQueue,
                statementDataCoder: statementDataCoder,
                logger: logger
            )

            let channelId = try channelFactory.createPeerRequestChannel(for: sessionId)

            let session = PeerSession<Message>(
                workQueue: workQueue,
                peer: request.peer,
                sessionId: sessionId,
                outgoingChannel: AnyOutgoingMessageChannel(outgoingChannel),
                incomingChannel: AnyIncomingMessageChannel(incomingChannel),
                peerSubscription: peerSubscription,
                initializer: sessionInitializer,
                priorityProvider: priorityProvider,
                statementDataCoder: statementDataCoder,
                peerRequestChannelId: channelId,
                logger: logger
            )

            let initializerDelegate = AnyPeerSessionInitializerDelegate(session)
            let incomingChannelDelegate = AnyIncomingMessageChannelDelegate(session)
            let outgoingChannelDelegate = AnyOutgoingMessageChannelDelegate(session)

            session.delegate = delegate
            incomingChannel.delegate = incomingChannelDelegate
            outgoingChannel.delegate = outgoingChannelDelegate
            sessionInitializer.delegate = initializerDelegate

            return AnyPeerSession(session)
        } catch {
            logger?.error("Unexpected error: \(error)")
            return nil
        }
    }
}

private extension PeerSessionFactory {
    func deriveOutgoingSharedSecret(
        for request: MessageExchange.SessionRequest,
        messageExchangeMode: MessageExchangeMode,
        identitySharedSecret: Data
    ) throws -> Data {
        switch messageExchangeMode {
        case .identity:
            return identitySharedSecret
        case .multidevice:
            guard !request.peer.devices.isEmpty else {
                return identitySharedSecret
            }
            guard let deviceEncryptionKeyFactory else {
                throw PeerSessionFactoryError.deviceEncryptionKeyFactoryMissing
            }
            let deviceEncryptor = try deviceEncryptionKeyFactory
                .makeEncryptor(remotePublicKey: request.peer.publicKey)
            return deviceEncryptor.sharedSecret
        }
    }

    func makeStatementDataCoder(
        for request: MessageExchange.SessionRequest,
        messageExchangeMode: MessageExchangeMode,
        identityEncryptor: MessageExchangeEncrypting,
        identityEncryptionKeyFactory: MessageExchangeEncryptionMaking,
        signer: StatementStoreSigning
    ) throws -> StatementDataCoding {
        switch messageExchangeMode {
        case .identity:
            return StatementDataCoder(encryptor: identityEncryptor, logger: logger)
        case .multidevice:
            guard !request.peer.devices.isEmpty else {
                // Peer devices are not yet known during the pre-handshake window
                // (before DeviceChatAccepted is exchanged). Fall back to identity
                // encryption so the session can be established and the handshake
                // can complete. Once devices are stored, updateSessions will
                // recreate the session with the full device-aware coder.
                // The same logic applies to `deriveOutgoingSharedSecret` and
                // `makePeerSubscription`.
                return StatementDataCoder(encryptor: identityEncryptor, logger: logger)
            }
            guard let deviceEncryptionKeyFactory else {
                throw PeerSessionFactoryError.deviceEncryptionKeyFactoryMissing
            }
            return try makeMultiDeviceAwareCoder(
                for: request,
                identityEncryptionKeyFactory: identityEncryptionKeyFactory,
                deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
                signer: signer
            )
        }
    }

    func makeMultiDeviceAwareCoder(
        for request: MessageExchange.SessionRequest,
        identityEncryptionKeyFactory: MessageExchangeEncryptionMaking,
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking,
        signer: StatementStoreSigning
    ) throws -> StatementDataCoding {
        let outgoingCoder = try makeMultiDeviceOutgoingCoder(
            deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
            peerPublicKey: request.peer.publicKey
        )
        let incomingCoders = try makeMultiDeviceIncomingCoders(
            peerDevices: request.peer.devices,
            identityEncryptionKeyFactory: identityEncryptionKeyFactory
        )
        return MultiDeviceAwareStatementDataCoder(
            outgoingCoder: outgoingCoder,
            incomingCoders: incomingCoders,
            multiDeviceCoder: MultiDeviceStatementDataCoder(
                deviceEncryptionKeyFactory: deviceEncryptionKeyFactory,
                logger: logger
            ),
            recipientDevices: makeRecipientDevices(peerDevices: request.peer.devices),
            ownStatementAccountId: signer.accountId,
            deviceKeysByAccountId: makeDeviceKeysByAccountId(peerDevices: request.peer.devices),
            logger: logger
        )
    }

    func makeMultiDeviceOutgoingCoder(
        deviceEncryptionKeyFactory: MessageExchangeEncryptionMaking,
        peerPublicKey: Data
    ) throws -> StatementDataCoding {
        let encryptor = try deviceEncryptionKeyFactory.makeEncryptor(remotePublicKey: peerPublicKey)
        return StatementDataCoder(encryptor: encryptor, logger: logger)
    }

    func makeMultiDeviceIncomingCoders(
        peerDevices: [MessageExchange.DeviceInfo],
        identityEncryptionKeyFactory: MessageExchangeEncryptionMaking
    ) throws -> [AccountId: StatementDataCoding] {
        try Dictionary(
            peerDevices.map { device in
                let encryptor = try identityEncryptionKeyFactory.makeEncryptor(
                    remotePublicKey: device.encryptionPublicKey
                )
                return (
                    device.statementAccountId,
                    StatementDataCoder(encryptor: encryptor, logger: logger) as StatementDataCoding
                )
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func makeRecipientDevices(peerDevices: [MessageExchange.DeviceInfo]) -> [RecipientDeviceInfo] {
        peerDevices.map {
            RecipientDeviceInfo(
                statementAccountId: $0.statementAccountId,
                encryptionPublicKey: $0.encryptionPublicKey
            )
        }
    }

    func makeDeviceKeysByAccountId(peerDevices: [MessageExchange.DeviceInfo]) -> [AccountId: Data] {
        Dictionary(
            peerDevices.map { ($0.statementAccountId, $0.encryptionPublicKey) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func makePeerSubscription(
        for request: MessageExchange.SessionRequest,
        messageExchangeMode: MessageExchangeMode,
        identitySharedSecret: Data,
        identityEncryptionKeyFactory: MessageExchangeEncryptionMaking,
        signer: StatementStoreSigning
    ) throws -> StatementSubscribing {
        switch messageExchangeMode {
        case .identity:
            let identitySessionId = try sessionIdFactory.createSessionId(
                for: .init(
                    ownAccountId: signer.accountId,
                    ownPin: request.own.pin,
                    peerAccountId: request.peer.accountId,
                    peerPin: request.peer.pin,
                    sharedSecret: identitySharedSecret
                )
            )

            return try pollerFactory.createSubscription(for: .init(
                accountId: request.peer.accountId,
                rawSessionId: identitySessionId.peer
            ))
        case .multidevice:
            guard !request.peer.devices.isEmpty else {
                let identitySessionId = try sessionIdFactory.createSessionId(
                    for: .init(
                        ownAccountId: signer.accountId,
                        ownPin: request.own.pin,
                        peerAccountId: request.peer.accountId,
                        peerPin: request.peer.pin,
                        sharedSecret: identitySharedSecret
                    )
                )
                return try pollerFactory.createSubscription(for: .init(
                    accountId: request.peer.accountId,
                    rawSessionId: identitySessionId.peer
                ))
            }

            let deviceSubscriptions = try request.peer.devices.map { device in
                let deviceEncryptor = try identityEncryptionKeyFactory
                    .makeEncryptor(remotePublicKey: device.encryptionPublicKey)
                let deviceSessionId = try sessionIdFactory.createSessionId(
                    for: .init(
                        ownAccountId: signer.accountId,
                        ownPin: request.own.pin,
                        peerAccountId: device.statementAccountId,
                        peerPin: request.peer.pin,
                        sharedSecret: deviceEncryptor.sharedSecret
                    )
                )

                return StatementSubscriptionInit(
                    accountId: device.statementAccountId,
                    rawSessionId: deviceSessionId.peer
                )
            }

            return try pollerFactory.createMatchAnySubscription(for: deviceSubscriptions)
        }
    }

    func makeOutgoingChannel(
        sessionId: MessageExchange.SessionId,
        signer: StatementStoreSigning,
        priorityProvider: PeerSessionPriorityProviding,
        requestQueue: AnyOutgoingRequestQueue<Message>
    ) throws -> OutgoingMessageChannel<M> {
        let channelId = try channelFactory.createRequestChannel(for: sessionId)

        return OutgoingMessageChannel(
            workQueue: workQueue,
            sessionId: sessionId,
            channelId: channelId,
            submitter: submitter,
            signer: signer,
            preSendHandler: preSendHandler,
            priorityProvider: priorityProvider,
            requestQueue: requestQueue,
            operationQueue: operationQueue,
            logger: logger
        )
    }

    func makeIncomingChannel(
        sessionId: MessageExchange.SessionId,
        signer: StatementStoreSigning,
        priorityProvider: PeerSessionPriorityProviding,
        statementDataCoder: StatementDataCoding
    ) throws -> IncomingMessageChannel<M> {
        let channelId = try channelFactory.createResponseChannel(for: sessionId)

        return IncomingMessageChannel(
            workQueue: workQueue,
            sessionId: sessionId,
            channelId: channelId,
            submitter: submitter,
            signer: signer,
            priorityProvider: priorityProvider,
            statementDataCoder: statementDataCoder,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}
