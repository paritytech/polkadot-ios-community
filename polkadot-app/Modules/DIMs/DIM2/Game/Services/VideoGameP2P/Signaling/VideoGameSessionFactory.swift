import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import Individuality

enum VideoGameSessionFactoryError: Error {
    case peerPublicKeyNotFound
}

protocol VideoGameSessionMaking {
    func makeSession(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession
}

final class VideoGameSessionFactory {
    private let ownSignKeyId: String
    private let serviceFactoryProvider: () -> MessageExchageServiceMaking
    private let identifierService: ChatIdentifierServiceProtocol
    private let chainRegistry: ChainRegistryProtocol
    private let chatChainId: ChainModel.Id
    private let logger: LoggerProtocol

    init(
        ownSignKeyId: String,
        serviceFactoryProvider: @escaping () -> MessageExchageServiceMaking,
        identifierService: ChatIdentifierServiceProtocol,
        chainRegistry: ChainRegistryProtocol,
        chatChainId: ChainModel.Id = AppConfig.Chains.chatChain,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.ownSignKeyId = ownSignKeyId
        self.serviceFactoryProvider = serviceFactoryProvider
        self.identifierService = identifierService
        self.chainRegistry = chainRegistry
        self.chatChainId = chatChainId
        self.logger = logger
    }
}

extension VideoGameSessionFactory: VideoGameSessionMaking {
    func makeSession(
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession {
        // Fetch peer's public key from CommunicationIdentifiers storage
        guard let peerPublicKey = try await identifierService.fetch(for: peerAccountId) else {
            throw VideoGameSessionFactoryError.peerPublicKeyNotFound
        }

        let pin = VideoGameSignalingSession.pin

        // Build Own using game candidate derivation paths with the video game room PIN
        let own = MessageExchange.Own(
            signKeyId: ownSignKeyId,
            encryptionKeyId: Chat.Contact.Own.gameEncryptionKeyId(),
            pin: pin
        )

        // Build Peer with the fetched public key and PIN
        let peer = MessageExchange.Peer(
            accountId: peerAccountId,
            publicKey: peerPublicKey,
            pin: pin,
            devices: []
        )

        // Each peer gets its own service factory
        let connection = try chainRegistry.getConnectionOrError(for: chatChainId)
        let serviceFactory = serviceFactoryProvider()

        let exchangeService = try serviceFactory.makeService(
            statementStoreConnection: StatementStoreConnection(
                connection: connection,
                retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
                logger: logger
            ),
            delegate: delegate
        )

        // Register the session request so the service starts listening
        let sessionRequest = MessageExchange.SessionRequest(own: own, peer: peer)
        exchangeService.updateSessions([sessionRequest])

        return VideoGameSignalingSession(
            gameIndex: gameIndex,
            peerAccountId: peerAccountId,
            exchangeService: exchangeService,
            peer: peer,
            logger: logger
        )
    }
}
