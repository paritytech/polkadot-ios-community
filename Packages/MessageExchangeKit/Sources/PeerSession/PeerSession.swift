import Foundation
import Foundation_iOS
import SubstrateSdk
import StatementStore
import SDKLogger

final class PeerSession<M: MessageExchange.CodableMessage>: TypeErasedDelegateStoring {
    typealias Message = M

    let peer: MessageExchange.Peer
    let sessionId: MessageExchange.SessionId

    weak var delegate: AnyPeerSessionDelegate<M>?

    private let workQueue: DispatchQueue
    private let outgoingChannel: AnyOutgoingMessageChannel<M>
    private let incomingChannel: AnyIncomingMessageChannel<M>
    private let statePublisher: any SessionStatePublishing<M>
    private let peerSubscription: any PeerSessionStatementSubscribing
    private let initializer: PeerSessionInitializing
    private let priorityProvider: PeerSessionPriorityProviding
    private let statementDataCoder: StatementDataCoding
    private let logger: SDKLoggerProtocol?

    private var state = InternalSessionState<M>.idle {
        didSet { didSetState() }
    }

    private var lastHandledPeerRequestIds = [PeerSessionRoute: String]()

    init(
        workQueue: DispatchQueue,
        peer: MessageExchange.Peer,
        sessionId: MessageExchange.SessionId,
        outgoingChannel: AnyOutgoingMessageChannel<M>,
        incomingChannel: AnyIncomingMessageChannel<M>,
        statePublisher: any SessionStatePublishing<M>,
        peerSubscription: any PeerSessionStatementSubscribing,
        initializer: PeerSessionInitializing,
        priorityProvider: PeerSessionPriorityProviding,
        statementDataCoder: StatementDataCoding,
        logger: SDKLoggerProtocol?
    ) {
        self.workQueue = workQueue
        self.peer = peer
        self.sessionId = sessionId
        self.outgoingChannel = outgoingChannel
        self.incomingChannel = incomingChannel
        self.statePublisher = statePublisher
        self.peerSubscription = peerSubscription
        self.initializer = initializer
        self.priorityProvider = priorityProvider
        self.statementDataCoder = statementDataCoder
        self.logger = logger

        initializeSession()
    }
}

extension PeerSession: PeerSessionProtocol {
    func addMessagesToQueue(_ messages: [Message]) {
        workQueue.async { [weak self] in
            self?.outgoingChannel.addMessagesToQueue(messages)
        }
    }
}

extension PeerSession: PeerSessionInitializerDelegate {
    func sessionInitializer(
        _: any PeerSessionInitializing,
        didInitializeWith result: SessionInitializationSuccess<M>
    ) {
        guard delegate != nil else {
            logger?.debug("Delegate is nil, skipping initialization")
            return
        }

        priorityProvider.expiry = result.priority
        statePublisher.restore(result.ownStates)
        for (route, ownState) in result.ownStates {
            lastHandledPeerRequestIds[route] = ownState.response?.requestId
        }
        state = .active(restoredRequests: result.outgoingState.outgoingRequests)

        delegate?.peerSession(
            self,
            didInitializeWithOutgoingMessages: result.outgoingState.initializedMessages
        )

        result.incomingState.peerRequests.forEach { peerRequest in
            _ = handlePeerRequest(peerRequest.request, route: peerRequest.route)
        }

        for (route, peerResponse) in result.outgoingState.peerResponses {
            _ = handlePeerResponse(peerResponse, route: route)
        }

        updatePolling()
    }

    func sessionInitializer(
        _ initializer: any PeerSessionInitializing,
        didFailToInitializeWith result: SessionInitializationFailure
    ) {
        guard delegate != nil else {
            logger?.debug("Delegate is nil, skipping initialization failure handling")
            return
        }

        let shouldReset = delegate?.peerSession(
            self,
            shouldResetAfter: result.error
        ) ?? MessageExchange.shouldResetSession

        guard shouldReset else {
            state = .idle
            updatePolling()
            return
        }

        sessionInitializer(
            initializer,
            didInitializeWith: .init(priority: result.expiry)
        )
    }
}

extension PeerSession: OutgoingMessageChannelDelegate {
    func messageChannel(
        _: any OutgoingMessageChanneling,
        didFinishAddingMessageToQueue message: Message,
        withError error: MessageExchange.AddToQueueError?
    ) {
        delegate?.peerSession(
            self,
            didFinishAddingMessageToQueue: message,
            withError: error
        )
    }

    func messageChannel(
        _: any OutgoingMessageChanneling,
        didPostMessages messages: [Message],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        delegate?.peerSession(
            self,
            didPostMessages: messages,
            withError: error
        )
    }

    func messageChannel(
        _: any OutgoingMessageChanneling,
        didDeliverMessages messages: [Message],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        delegate?.peerSession(
            self,
            didDeliverMessages: messages,
            withError: error
        )
    }

    func messageChannel(
        _: any OutgoingMessageChanneling,
        didCompactMessages compactedMessage: Message,
        originalMessages: [Message]
    ) {
        delegate?.peerSession(
            self,
            didCompactMessages: compactedMessage,
            originalMessages: originalMessages
        )
    }

    func statementSubmitFailed(with error: Error) {
        if isStatementErrorRequiresReinitialization(error) {
            initializeSession()
            return
        }

        let shouldReinit = delegate?.peerSession(
            self,
            shouldReinitializeAfterSubmitError: error
        ) ?? MessageExchange.shouldReinitializeSession

        if shouldReinit {
            initializeSession()
        }
    }
}

private extension PeerSession {
    func didSetState() {
        logger?.debug("State updated to \(state)")
        delegate?.peerSession(self, didUpdateState: state.toPeerSessionState())

        switch state {
        case let .active(restoredRequests):
            outgoingChannel.activate(restoringState: restoredRequests)
        case .idle,
             .initializing:
            outgoingChannel.deactivate()
        }
    }

    func updatePolling() {
        if state.isActive {
            peerSubscription.start { [weak self] sessionStatement in
                self?.handlePollingStatement(sessionStatement) ?? false
            }
        } else {
            peerSubscription.stop()
        }
    }

    func initializeSession() {
        workQueue.async { [weak self] in
            self?.performInitializeSession()
        }
    }

    func performInitializeSession() {
        guard !state.isInitializing else {
            logger?.debug("Already initializing")
            return
        }

        state = .initializing
        updatePolling()

        initializer.initializeSession()
    }

    func isStatementErrorRequiresReinitialization(_ error: Error) -> Bool {
        guard let submittionError = error as? StatementSubmitError else {
            return false
        }

        switch submittionError {
        case let .rejected(reason):
            // channelPriorityTooLow is delegated to the app: a routine burst of
            // outgoing requests can outbid each other on expiry, and that does
            // not warrant tearing down the session.
            return reason != .channelPriorityTooLow
        case .invalid,
             .internalError:
            return true
        case .unexpectedStatus:
            return false
        }
    }

    func handlePollingStatement(_ sessionStatement: PeerSessionStatement) -> StatementHandlingStatus {
        guard delegate != nil else {
            logger?.debug("Delegate is nil, skipping statement")
            return false
        }

        guard state.isActive else {
            logger?.debug("Session is not active")
            return false
        }

        let route = sessionStatement.route

        do {
            guard let payload = sessionStatement.statement.getScaleEncodedPayload() else {
                throw StatementDataDecodingError.decodingFailed
            }

            let outcome: StatementDataDecodingResult<Message> = try statementDataCoder.decodeFromScaleEncodedPayload(
                payload,
                senderAccountId: sessionStatement.topicAccountId,
                route: route
            )

            switch outcome {
            case let .statementData(.state(state)):
                return handlePeerState(state, route: route)
            case .statementData(.multistate):
                // The peer's devices aren't known yet (before DeviceChatAccepted), so the envelope can't be opened.
                logger?.warning("Skipping multi-device envelope: peer devices not yet known")
                return false
            case let .partial(response, requestId, error):
                let handledResponse = response.map { handlePeerResponse($0, route: route) } ?? false
                let handledRequest = handleFailedPeerRequest(requestId, error: error, route: route)
                return handledResponse || handledRequest
            }
        } catch {
            // Anyone can publish under a topic; only statements that decrypt under the session key count.
            logger?.debug("Skipping undecodable statement on route \(route): \(error)")
            return true
        }
    }

    func handlePeerState(
        _ state: MessageExchange.SessionState<Message>,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus {
        let handledResponse = state.response.map { handlePeerResponse($0, route: route) } ?? false
        let handledRequest = state.request.map { handlePeerRequest($0, route: route) } ?? false
        return handledResponse || handledRequest
    }

    func handlePeerRequest(
        _ request: MessageExchange.Request<Message>,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus {
        let requestId = request.requestId

        // The peer republishes its state for every ack it gives, re-delivering the same pending request.
        guard lastHandledPeerRequestIds[route] != requestId else {
            logger?.debug("Request \(requestId) on route \(route) was already handled")
            return true
        }

        lastHandledPeerRequestIds[route] = requestId

        logger?.debug(
            "Successfully received request \(requestId) with \(request.messages.count) messages on route \(route)"
        )

        delegate?.peerSession(
            self,
            didReceiveMessages: request.messages
        ) { [weak self] responseCode in
            self?.workQueue.async { [weak self] in
                self?.incomingChannel.sendResponse(
                    with: responseCode,
                    forRequestId: requestId,
                    route: route
                )
            }
        }

        return true
    }

    func handleFailedPeerRequest(
        _ requestId: String,
        error: Error,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus {
        guard lastHandledPeerRequestIds[route] != requestId else {
            return true
        }

        lastHandledPeerRequestIds[route] = requestId

        logger?.debug("Received failed decoding request \(requestId) \(error)")

        delegate?.peerSessionDidReceiveMessagesError(self) { [weak self] responseCode in
            self?.workQueue.async { [weak self] in
                self?.incomingChannel.sendResponse(
                    with: responseCode,
                    forRequestId: requestId,
                    route: route
                )
            }
        }

        return true
    }

    func handlePeerResponse(
        _ response: MessageExchange.Response,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus {
        if outgoingChannel.handleResponse(response, route: route) {
            initializer.setLastHandledResponseId(response.requestId, route: route)
            return true
        } else {
            logger?.debug("Response \(response.requestId) on route \(route) was not handled by outgoing channel")
            return false
        }
    }
}

public enum PeerSessionState {
    case idle
    case initializing
    case active
}

enum InternalSessionState<M: MessageExchange.CodableMessage> {
    case idle
    case initializing
    case active(restoredRequests: [PeerSessionRoute: OutgoingRequest<M>])

    var isInitializing: Bool {
        switch self {
        case .idle,
             .active:
            false
        case .initializing:
            true
        }
    }

    var isActive: Bool {
        switch self {
        case .idle,
             .initializing:
            false
        case .active:
            true
        }
    }

    func toPeerSessionState() -> PeerSessionState {
        switch self {
        case .idle:
            .idle
        case .initializing:
            .initializing
        case .active:
            .active
        }
    }
}
