import Foundation
import CommonService
import SubstrateSdk
import Operation_iOS

protocol CallCoordinating: AnyObject {
    func handleIncomingCall(
        message: Chat.RemoteMessage,
        from peer: CallPeer
    ) async

    func initiateCall(with peer: CallPeer, callType: ChatCallType)
}

final class RealCallCoordinator {
    // Stale Threshold in milliseconds (30 sec)
    private static let staleOfferThreshold: TimeInterval = 30 * 1_000

    private weak var receiver: ChatCallMessageReceiving?

    let chainRegistry: ChainRegistryProtocol
    let signalingChainId: ChainModel.Id
    let callKitManager: VoIPCallKitManaging
    let presentationManager: ChatCallPresentationManaging
    let messagesStorageService: MessagesLocalStorageServicing
    let outboxService: ChatOutboxServicing
    let turnService: TURNCredentialsProviding
    let logger: LoggerProtocol

    private var activeCallKitDataTask: Task<Void, Never>?

    init(
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        signalingChainId: ChainModel.Id = AppConfig.Chains.chatChain,
        callKitManager: VoIPCallKitManaging = VoIPCallKitManager.shared,
        presentationManager: ChatCallPresentationManaging,
        messagesStorageService: MessagesLocalStorageServicing = MessagesLocalStorageService(),
        outboxService: ChatOutboxServicing,
        turnService: TURNCredentialsProviding,
        logger: LoggerProtocol
    ) {
        self.chainRegistry = chainRegistry
        self.signalingChainId = signalingChainId
        self.callKitManager = callKitManager
        self.presentationManager = presentationManager
        self.messagesStorageService = messagesStorageService
        self.outboxService = outboxService
        self.turnService = turnService
        self.logger = logger
        setupCallKit()
    }

    deinit {
        throttleCallKit()
    }
}

private extension RealCallCoordinator {
    func startCall(with peer: CallPeer, role: CallRole, callType: ChatCallType) {
        let signaler = ChatPeerConnectionSignaler(
            peerAccountId: peer.accountId,
            callType: callType,
            outboxService: outboxService,
            logger: logger
        )

        let engine = CallEngine(
            signaling: signaler,
            role: role,
            initialCallType: callType,
            purpose: WebRTCConnectionPurpose.call.rawValue,
            configFactory: WebRTCConfigFactory(turnService: turnService),
            logger: logger
        )

        receiver = signaler

        presentationManager.presentCall(with: peer, using: engine, role: role, callType: callType)
    }

    func setupCallKit() {
        activeCallKitDataTask = Task { [weak self] in
            guard let sequence = self?.callKitManager.observeActiveCallData() else {
                return
            }
            do {
                for try await callData in sequence {
                    self?.handleActiveCallKitData(callData)
                }
            } catch {
                self?.logger.error("Active call data task failure: \(error.localizedDescription)")
            }
        }
    }

    func throttleCallKit() {
        activeCallKitDataTask?.cancel()
        activeCallKitDataTask = nil
    }

    func handleActiveCallKitData(_ callData: VoIPCallKitData?) {
        chainRegistry.setConnectionEnforced(callData != nil, for: signalingChainId)
    }

    func isOfferStale(timestamp: UInt64) -> Bool {
        let nowMs = Date().toChatTimestamp()
        guard nowMs > timestamp else {
            return false
        }
        let ageMs = nowMs - timestamp
        return ageMs > UInt64(Self.staleOfferThreshold)
    }

    func sendDataChannelClosed(to peerAccountId: AccountId, offerId: String) {
        let content = Chat.RemoteMessageContentV1.MessageContent.DataChannelClosedContent(
            offerId: offerId
        )
        let local = Chat.LocalMessage.newMessageToPerson(
            peerAccountId,
            content: .call(.closed(content))
        )
        let operation = messagesStorageService.insertOrUpdate([local])
        Task { [logger, messageId = local.messageId] in
            do {
                try await operation.asyncExecute()
            } catch {
                logger.error("Failed to persist call closed message \(messageId): \(error)")
            }
        }
    }
}

extension RealCallCoordinator: CallCoordinating {
    func handleIncomingCall(
        message: Chat.RemoteMessage,
        from peer: CallPeer
    ) async {
        if let receiver, receiver.peerAccountId == peer.accountId {
            await receiver.receive(message: message)
            return
        }

        guard case let .dataChannelOffer(offer) = message.versioned.ensureV1()?.content else {
            return
        }

        guard !isOfferStale(timestamp: message.timestamp) else {
            logger.warning("Stale call offer received: \(message.messageId)")
            sendDataChannelClosed(to: peer.accountId, offerId: message.messageId)
            return
        }

        guard receiver == nil else {
            logger.warning("Call is busy, rejecting offer: \(message.messageId)")
            sendDataChannelClosed(to: peer.accountId, offerId: message.messageId)
            return
        }

        startCall(
            with: peer,
            role: .acceptor,
            callType: ChatCallType(remoteType: offer.purpose)
        )

        await receiver?.receive(message: message)
    }

    func initiateCall(with peer: CallPeer, callType: ChatCallType) {
        startCall(with: peer, role: .initiator, callType: callType)
    }
}
