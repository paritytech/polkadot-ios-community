import Foundation
import SubstrateSdk
import MessageExchangeKit
import StatementStore
import Operation_iOS
import SDKLogger

protocol OutgoingChatRequestServicing {
    /// Only the outer statement is signed by `signer`; the inner proof and the session stay on `ownKeyId`.
    func send(
        message: Chat.RequestMessage,
        to peer: MessageExchange.Peer,
        ownKeyId: MessageExchange.Own,
        signer: StatementStoreSigning
    ) async throws
}

enum OutgoingChatRequestServiceError: Error {
    case unexpected(String)
}

final class OutgoingChatRequestService {
    private let statementStoreSubmitter: StatementStoreSubmitting
    private let priorityFactory: StatementPriorityMaking
    private let requestFactory: ChatRequestFactoryProtocol
    private let channelFactory: ChatRequestChannelFactoryProtocol
    private let logger: SDKLoggerProtocol

    init(
        statementStoreSubmitter: StatementStoreSubmitting,
        requestFactory: ChatRequestFactoryProtocol,
        priorityFactory: StatementPriorityMaking,
        channelFactory: ChatRequestChannelFactoryProtocol,
        logger: SDKLoggerProtocol
    ) {
        self.statementStoreSubmitter = statementStoreSubmitter
        self.priorityFactory = priorityFactory
        self.channelFactory = channelFactory
        self.requestFactory = requestFactory
        self.logger = logger
    }
}

extension OutgoingChatRequestService: OutgoingChatRequestServicing {
    func send(
        message: Chat.RequestMessage,
        to peer: MessageExchange.Peer,
        ownKeyId: MessageExchange.Own,
        signer: StatementStoreSigning
    ) async throws {
        guard let pagination = ChatRequest.paginationDay(from: Date()) else {
            throw OutgoingChatRequestServiceError.unexpected("Invalid pagination day")
        }

        let topic1 = try ChatRequest.allPeerStatementsTopic(from: peer.accountId)
        let topic2 = try ChatRequest.paginationTopic(from: peer.accountId, day: pagination.day)
        let channel = try channelFactory.outgoingChannel(with: peer, ownKeyId: ownKeyId)

        let remoteRequest = try requestFactory.createRemoteRequest(
            from: message,
            peerEncryptionPubKey: peer.publicKey,
            peerAccountId: peer.accountId,
            ownKeyId: ownKeyId
        )

        let payload = try remoteRequest.scaleEncoded()
        let scaleEncodedPayload = try payload.scaleEncoded()

        let builder = StatementSubmitParametersBuilder(
            signer: signer,
            logger: logger
        )
        .addTopic1(topic1)
        .addTopic2(topic2)
        .addTopic3(channel) // we add channel as topic2 also for easy discovery
        .addChannel(channel)
        .addExpiry(priorityFactory.makeTimestampPriority())
        .addScaleEncodedPayload(scaleEncodedPayload)

        try await statementStoreSubmitter.submitStatement(with: builder)
    }
}
