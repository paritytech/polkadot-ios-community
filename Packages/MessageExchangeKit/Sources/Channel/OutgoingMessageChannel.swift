import Foundation
import Operation_iOS
import StatementStore
import SDKLogger

final class OutgoingMessageChannel<M: MessageExchange.CodableMessage>: @unchecked Sendable {
    typealias Message = M

    weak var delegate: AnyOutgoingMessageChannelDelegate<M>?

    private let workQueue: DispatchQueue
    private let sessionId: MessageExchange.SessionId
    private let channelId: StatementFixedFieldConvertible
    private let submitter: StatementStoreSubmitting
    private let signer: StatementStoreSigning
    private let preSendHandler: AnyPeerSessionPreSendHandler<M>
    private let priorityProvider: PeerSessionPriorityProviding
    private let requestQueue: AnyOutgoingRequestQueue<M>
    private let operationQueue: OperationQueue
    private let logger: SDKLoggerProtocol?
    private var submissionTask: Task<Void, Never>?

    private var isActive = false

    init(
        workQueue: DispatchQueue,
        sessionId: MessageExchange.SessionId,
        channelId: StatementFixedFieldConvertible,
        submitter: StatementStoreSubmitting,
        signer: StatementStoreSigning,
        preSendHandler: AnyPeerSessionPreSendHandler<M>,
        priorityProvider: PeerSessionPriorityProviding,
        requestQueue: AnyOutgoingRequestQueue<M>,
        operationQueue: OperationQueue,
        logger: SDKLoggerProtocol?
    ) {
        self.workQueue = workQueue
        self.sessionId = sessionId
        self.channelId = channelId
        self.submitter = submitter
        self.signer = signer
        self.preSendHandler = preSendHandler
        self.priorityProvider = priorityProvider
        self.requestQueue = requestQueue
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension OutgoingMessageChannel: OutgoingMessageChanneling {
    func handleResponse(_ response: MessageExchange.Response) -> StatementHandlingStatus {
        assert(delegate != nil, "Delegate should not be nil")

        guard response.requestId == requestQueue.currentRequest?.requestId else {
            return false
        }

        logger?.debug("Got new response \(response)")

        if response.responseCode.isSuccess {
            logger?.debug("Message was delivered successfully")
            handleMessageDeliveringFinish(with: nil)
        } else {
            logger?.debug("Got failed response: \(response.responseCode)")
            handleMessageDeliveringFinish(with: .gotFailedResponse(response.responseCode))
        }

        return true
    }

    func restoreState(from request: OutgoingRequest<Message>?) {
        requestQueue.currentRequest = request
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive

        if isActive {
            logger?.debug("Trying to send messages as channel became active")
            let hasExtendedRequest = requestQueue.attemptRequestExtensionFromQueue()
            sendNextRequest(resendsCurrentRequest: hasExtendedRequest)
        }
    }

    func addMessageToQueue(_ message: Message) {
        let result = requestQueue.addMessage(message, isChannelActive: isActive)

        switch result {
        case let .success(result):
            handleAddToQueueResult(result, for: message)
        case let .failure(error):
            handleAddToQueueError(error, for: message)
        }
    }
}

private extension OutgoingMessageChannel {
    func handleAddToQueueResult(_ result: MessageExchange.AddToQueueResult, for message: Message) {
        logger?.debug("Added message to queue")

        delegate?.messageChannel(
            self,
            didFinishAddingMessageToQueue: message,
            withError: nil
        )

        switch result {
        case .appendedToCurrentRequest:
            sendNextRequest(resendsCurrentRequest: true)
        case .queued:
            sendNextRequest(resendsCurrentRequest: false)
        case .ignored:
            break
        }
    }

    func handleAddToQueueError(_ error: MessageExchange.AddToQueueError, for message: Message) {
        logger?.error("Failed to add message to queue: \(error)")

        delegate?.messageChannel(
            self,
            didFinishAddingMessageToQueue: message,
            withError: error
        )
    }

    func sendNextRequest(resendsCurrentRequest: Bool) {
        guard isActive else {
            logger?.debug("Channel is not in the active state")
            return
        }

        guard resendsCurrentRequest || requestQueue.currentRequest == nil else {
            logger?.debug("Already sending messages, waiting")
            return
        }

        guard let newRequest = newRequest(resendsCurrentRequest: resendsCurrentRequest) else {
            logger?.debug("No messages in queue")
            return
        }

        for message in newRequest.messages {
            preSendHandler.handlePreSend(message: message)
        }

        requestQueue.currentRequest = newRequest

        sendOutgoingRequest(newRequest)
    }

    func newRequest(resendsCurrentRequest: Bool) -> OutgoingRequest<Message>? {
        resendsCurrentRequest
            ? requestQueue.currentRequest
            : requestQueue.dequeueMessagesForNewRequest()
    }

    func handleMessagePostingFinish(with error: Error?) {
        let messages = requestQueue.currentRequest?.messages ?? []

        if let error {
            logger?.error("Failed to post messages: \(error.localizedDescription)")
            finishRequestSending()
        } else {
            logger?.debug("Successfully posted messages, waiting for delivering")
        }

        delegate?.messageChannel(
            self,
            didPostMessages: messages,
            withError: error.map { .failedToPost($0) }
        )
    }

    func handleMessageDeliveringFinish(with error: MessageExchange.OutgoingMessageError?) {
        let messages = requestQueue.currentRequest?.messages ?? []

        if let error {
            logger?.error("Failed to deliver messages: \(error.localizedDescription)")
        } else {
            logger?.debug("Successfully delivered messages")
        }

        finishRequestSending()

        delegate?.messageChannel(
            self,
            didDeliverMessages: messages,
            withError: error
        )
    }

    func finishRequestSending() {
        requestQueue.currentRequest = nil

        logger?.debug("Trying to send more messages")
        sendNextRequest(resendsCurrentRequest: false)
    }

    func sendOutgoingRequest(_ outgoingRequest: OutgoingRequest<Message>) {
        let expiry = priorityProvider.incrementedExpiry()
        let requestId = outgoingRequest.requestId

        let builder = StatementSubmitParametersBuilder(
            signer: signer,
            logger: logger
        )
        .addTopic1(sessionId.own)
        .addChannel(channelId)
        .addExpiry(expiry)
        .addScaleEncodedPayload(outgoingRequest.scaleEncodedPayload)

        logger?.debug("Going to send request \(requestId) with priority \(expiry)")

        submissionTask?.cancel()

        submissionTask = Task { [weak self] in
            do {
                try await self?.submitter.submitStatement(with: builder)
                self?.logger?.debug("Request \(requestId) sent successfully")

                self?.workQueue.async {
                    self?.handleMessagePostingFinish(with: nil)
                }

            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.logger?.error("Failed to send request \(requestId): \(error)")

                self?.workQueue.async {
                    self?.handleMessagePostingFinish(with: error)
                    self?.delegate?.statementSubmitFailed(with: error)
                }
            }
        }
    }
}
