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
    private let peerSubscription: StatementSubscribing
    private let initializer: PeerSessionInitializing
    private let priorityProvider: PeerSessionPriorityProviding
    private let statementDataCoder: StatementDataCoding
    private let peerRequestChannelId: StatementFixedFieldConvertible
    private let logger: SDKLoggerProtocol?

    private var state = PeerSessionState.idle {
        didSet { didSetState() }
    }

    init(
        workQueue: DispatchQueue,
        peer: MessageExchange.Peer,
        sessionId: MessageExchange.SessionId,
        outgoingChannel: AnyOutgoingMessageChannel<M>,
        incomingChannel: AnyIncomingMessageChannel<M>,
        peerSubscription: StatementSubscribing,
        initializer: PeerSessionInitializing,
        priorityProvider: PeerSessionPriorityProviding,
        statementDataCoder: StatementDataCoding,
        peerRequestChannelId: StatementFixedFieldConvertible,
        logger: SDKLoggerProtocol?
    ) {
        self.workQueue = workQueue
        self.peer = peer
        self.sessionId = sessionId
        self.outgoingChannel = outgoingChannel
        self.incomingChannel = incomingChannel
        self.peerSubscription = peerSubscription
        self.initializer = initializer
        self.priorityProvider = priorityProvider
        self.statementDataCoder = statementDataCoder
        self.peerRequestChannelId = peerRequestChannelId
        self.logger = logger

        initializeSession()
    }
}

extension PeerSession: PeerSessionProtocol {
    func addMessageToQueue(_ message: Message) {
        workQueue.async { [weak self] in
            self?.outgoingChannel.addMessageToQueue(message)
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
        outgoingChannel.restoreState(from: result.outgoingState.outgoingRequest)
        state = .active

        delegate?.peerSession(
            self,
            didInitializeWithOutgoingMessages: result.outgoingState.initializedMessages
        )

        // TODO: Response statements share the same response channel, so replying to
        // multiple restored requests can leave only the latest ACK visible to an
        // offline sender. Message delivery is still done per request here; revisit
        // the protocol if sender-side ACK recovery must cover every request id.
        result.incomingState.peerRequests.forEach { peerRequest in
            _ = handlePeerRequest(peerRequest)
        }

        if let peerResponse = result.outgoingState.peerResponse {
            _ = handlePeerResponse(peerResponse)
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

extension PeerSession: IncomingMessageChannelDelegate, OutgoingMessageChannelDelegate {
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
        delegate?.peerSession(self, didUpdateState: state)
        outgoingChannel.setActive(state == .active)
    }

    func updatePolling() {
        if state == .active {
            peerSubscription.start { [weak self] statement in
                self?.handlePollingStatement(statement) ?? false
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
        guard state != .initializing else {
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
        case .rejected,
             .invalid,
             .internalError:
            return true
        case .unexpectedStatus:
            return false
        }
    }

    func handlePollingStatement(_ statement: Statement) -> StatementHandlingStatus {
        guard delegate != nil else {
            logger?.debug("Delegate is nil, skipping statement")
            return false
        }

        guard state == .active else {
            logger?.debug("Session is not active")
            return false
        }

        guard let encodedDataPayload = statement.getScaleEncodedPayload() else {
            return handleIncomingMessageError(.decodingFailed, for: statement)
        }

        let senderAccountId = statement.getSenderAccountId()

        do {
            let outcome: StatementDataDecodingResult<Message> = try statementDataCoder
                .decodeFromScaleEncodedPayload(encodedDataPayload, senderAccountId: senderAccountId)

            switch outcome {
            case let .statementData(statementData):
                return handleStatementData(statementData)
            case let .requestId(requestId, error):
                return handleFailedPeerRequest(requestId, error: error)
            }
        } catch {
            return handleIncomingMessageError(makeIncomingMessageError(error: error), for: statement)
        }
    }

    func handleStatementData(_ statementData: StatementData<Message>) -> StatementHandlingStatus {
        switch statementData {
        case let .request(request):
            return handlePeerRequest(request)
        case let .response(response):
            return handlePeerResponse(response)
        case .multirequest,
             .multiresponse:
            // Peer sent a multi-device envelope but this session uses a legacy coder
            // that cannot decrypt the inner payload. This happens when the peer's
            // device_added message hasn't been received yet.
            logger?.warning("Skipping multi-device envelope: peer devices not yet known")
            return false
        }
    }

    func handlePeerRequest(_ request: MessageExchange.Request<Message>) -> StatementHandlingStatus {
        let requestId = request.requestId

        logger?.debug("Successfully received request \(requestId) with \(request.messages.count) messages")

        delegate?.peerSession(
            self,
            didReceiveMessages: request.messages
        ) { [weak self] responseCode in
            self?.workQueue.async { [weak self] in
                self?.incomingChannel.sendResponse(
                    with: responseCode,
                    forRequestId: requestId
                )
            }
        }

        return true
    }

    func handleFailedPeerRequest(_ requestId: String, error: Error) -> StatementHandlingStatus {
        logger?.debug("Received failed decoding request \(requestId) \(error)")

        delegate?.peerSessionDidReceiveMessagesError(self) { [weak self] responseCode in
            self?.workQueue.async { [weak self] in
                self?.incomingChannel.sendResponse(
                    with: responseCode,
                    forRequestId: requestId
                )
            }
        }

        return true
    }

    func handlePeerResponse(_ response: MessageExchange.Response) -> StatementHandlingStatus {
        if outgoingChannel.handleResponse(response) {
            initializer.setLastHandledResponseId(response.requestId)
            return true
        } else {
            return false
        }
    }

    func handleIncomingMessageError(
        _ error: MessageExchange.IncomingMessageError,
        for statement: Statement
    ) -> StatementHandlingStatus {
        let shouldIgnore = delegate?.peerSession(
            self,
            shouldIgnoreStatementAfter: error
        ) ?? MessageExchange.shouldIgnoreStatement

        guard
            let channel = statement.getChannel(),
            let requestChannel = try? peerRequestChannelId.fixedStatementFieldData(),
            channel == requestChannel
        else {
            logger?.error("Failed to handle incoming message: \(error)")
            return shouldIgnore
        }

        logger?.error("Failed to handle incoming request: \(error)")

        return shouldIgnore
    }

    func makeIncomingMessageError(error: Error) -> MessageExchange.IncomingMessageError {
        switch error {
        case let decodingError as StatementDataDecodingError:
            return makeIncomingMessageError(decodingError: decodingError)
        case let multiDeviceError as MultiDeviceDecodingError:
            return makeIncomingMessageError(multiDeviceError: multiDeviceError)
        default:
            logger?.error("Unexpected error: \(error)")
            return .decodingFailed
        }
    }

    func makeIncomingMessageError(
        decodingError: StatementDataDecodingError
    ) -> MessageExchange.IncomingMessageError {
        switch decodingError {
        case .decodingFailed:
            .decodingFailed
        case .decryptionFailed:
            .decryptionFailed
        }
    }

    func makeIncomingMessageError(
        multiDeviceError: MultiDeviceDecodingError
    ) -> MessageExchange.IncomingMessageError {
        switch multiDeviceError {
        case .payloadDecodingFailed:
            .decodingFailed
        case .deviceEntryNotFound,
             .oneshotKeyDecryptionFailed,
             .payloadDecryptionFailed:
            .decryptionFailed
        }
    }
}

public enum PeerSessionState {
    case idle
    case initializing
    case active
}
