import Foundation
import SubstrateSdk
import AsyncExtensions
import Operation_iOS

enum ChatPeerConnectionSignalerError: Error {
    case undefinedOfferId
    case offerIdMismatch(String?, String)
}

actor ChatPeerConnectionSignaler {
    nonisolated let peerAccountId: AccountId
    nonisolated let callType: ChatCallType
    nonisolated let messagesStorageService: MessagesLocalStorageServicing
    nonisolated let outboxService: ChatOutboxServicing
    nonisolated let providerFactory: ChatMessageDataProviderMaking
    nonisolated let workQueue: DispatchQueue
    nonisolated let logger: LoggerProtocol
    nonisolated let sdpCoder = SdpCoder()

    private nonisolated let subject = AsyncReplaySubject<PeerConnectionSignal>(bufferSize: 100)

    private var offerId: String?
    private var processedMessageIds = Set<Chat.MessageId>()

    init(
        peerAccountId: AccountId,
        callType: ChatCallType,
        outboxService: ChatOutboxServicing,
        messagesStorageService: MessagesLocalStorageServicing = MessagesLocalStorageService(),
        providerFactory: ChatMessageDataProviderMaking = ChatMessageDataProviderFactory(),
        workQueue: DispatchQueue = DispatchQueue(
            label: "ChatPeerConnectionSignaler.queue",
            qos: .utility
        ),
        logger: LoggerProtocol
    ) {
        self.peerAccountId = peerAccountId
        self.callType = callType
        self.outboxService = outboxService
        self.messagesStorageService = messagesStorageService
        self.providerFactory = providerFactory
        self.workQueue = workQueue
        self.logger = logger
    }

    deinit {
        logger.debug("Deinit")
    }
}

private extension ChatPeerConnectionSignaler {
    enum Batch {
        case offer(SdpCoderSetup)
        case answer(SdpCoderSetup)
        case candidates([PeerConnectionCandidate])
        case closed
    }

    func makeBatch(_ signal: PeerConnectionSignal) -> Batch {
        switch signal {
        case let .offer(sdp):
            .offer(SdpCoderSetup(setupSdp: sdp, candidates: []))
        case let .answer(sdp):
            .answer(SdpCoderSetup(setupSdp: sdp, candidates: []))
        case let .candidates(candidates):
            .candidates(candidates)
        case .closed:
            .closed
        }
    }

    func sendBatch(_ batch: Batch) async throws -> Chat.MessageId? {
        switch batch {
        case let .offer(setup):
            let minimizedSdp = try sdpCoder.encodeSetup(setup)
            let content = Chat.RemoteMessageContentV1.MessageContent.DataChannelOfferContent(
                sdp: minimizedSdp,
                purpose: callType.toRemote()
            )

            logger.debug("Sent message with offer: \(minimizedSdp.count)")
            logger.debug("Setup candidates: \(setup.candidates.count)")

            let message = makeLocalCallMessage(.offer(content))
            offerId = message.messageId
            try await persistCallMessage(message)
            return message.messageId
        case let .answer(setup):
            guard let offerId else {
                throw ChatPeerConnectionSignalerError.undefinedOfferId
            }

            let minimizedSdp = try sdpCoder.encodeSetup(setup)

            logger.debug("Sent message with answer: \(minimizedSdp.count)")
            logger.debug("Setup candidates: \(setup.candidates.count)")

            let content = Chat.RemoteMessageContentV1.MessageContent.DataChannelAnswerContent(
                offerId: offerId,
                sdp: minimizedSdp
            )

            let message = makeLocalCallMessage(.answer(content))
            try await persistCallMessage(message)
            return message.messageId
        case let .candidates(candidates):
            guard let offerId else {
                throw ChatPeerConnectionSignalerError.undefinedOfferId
            }

            let minimizedSdp = try sdpCoder.encodeCandidates(candidates)

            let content = Chat.RemoteMessageContentV1.MessageContent.DataChannelCandidatesContent(
                offerId: offerId,
                sdp: minimizedSdp
            )

            logger.debug("Sent message with candidates: \(minimizedSdp.count)")

            let remoteMessage = Chat.RemoteMessage.newMessage(with: .dataChannelCandidates(content))
            outboxService.sendDirectly(remoteMessage, to: peerAccountId)
            return nil
        case .closed:
            guard let offerId else {
                throw ChatPeerConnectionSignalerError.undefinedOfferId
            }

            let content = Chat.RemoteMessageContentV1.MessageContent.DataChannelClosedContent(
                offerId: offerId
            )

            logger.debug("Sent close message for offer: \(offerId)")

            let message = makeLocalCallMessage(.closed(content))
            try await persistCallMessage(message)
            return message.messageId
        }
    }

    func makeLocalCallMessage(
        _ payload: Chat.LocalMessage.Content.CallSignalingPayload
    ) -> Chat.LocalMessage {
        Chat.LocalMessage.newMessageToPerson(
            peerAccountId,
            content: .call(payload)
        )
    }

    func persistCallMessage(_ message: Chat.LocalMessage) async throws {
        let operation = messagesStorageService.insertOrUpdate([message])
        try await operation.asyncExecute()
    }
}

extension ChatPeerConnectionSignaler: PeerConnectionSignaling {
    nonisolated var signals: AnyAsyncSequence<PeerConnectionSignal> {
        subject.eraseToAnyAsyncSequence()
    }

    func send(_ signal: PeerConnectionSignal) async throws -> PeerConnectionSignalStateObserving? {
        let batch = makeBatch(signal)
        guard let messageId = try await sendBatch(batch) else {
            return ImmediateSignalStateObserver()
        }

        return ChatSignalStateObserver(
            messageId: messageId,
            providerFactory: providerFactory,
            workQueue: workQueue
        )
    }
}

extension ChatPeerConnectionSignaler: ChatCallMessageReceiving {
    func receive(message: Chat.RemoteMessage) async {
        guard !processedMessageIds.contains(message.messageId) else {
            logger.warning("Message already processed: \(message.messageId)")
            return
        }

        processedMessageIds.insert(message.messageId)

        do {
            switch message.versioned.ensureV1()?.content {
            case let .dataChannelOffer(content):
                let decodedSetup = try sdpCoder.decodeSetup(content.sdp)

                offerId = message.messageId
                subject.send(.offer(decodedSetup.setupSdp))

                if !decodedSetup.candidates.isEmpty {
                    subject.send(.candidates(decodedSetup.candidates))
                }

            case let .dataChannelAnswer(content):
                guard content.offerId == offerId else {
                    throw ChatPeerConnectionSignalerError.offerIdMismatch(
                        offerId,
                        content.offerId
                    )
                }

                let decodedSetup = try sdpCoder.decodeSetup(content.sdp)
                subject.send(.answer(decodedSetup.setupSdp))

                if !decodedSetup.candidates.isEmpty {
                    subject.send(.candidates(decodedSetup.candidates))
                }

            case let .dataChannelCandidates(content):
                guard content.offerId == offerId else {
                    throw ChatPeerConnectionSignalerError.offerIdMismatch(
                        offerId,
                        content.offerId
                    )
                }

                let decodedCandidates = try sdpCoder.decodeCandidates(content.sdp)

                subject.send(.candidates(decodedCandidates))

            case let .dataChannelClosed(content):
                guard content.offerId == offerId else {
                    throw ChatPeerConnectionSignalerError.offerIdMismatch(
                        offerId,
                        content.offerId
                    )
                }

                subject.send(.closed)

            default:
                break
            }
        } catch {
            logger.error("Sdp decoding failed: \(error)")
        }
    }
}
