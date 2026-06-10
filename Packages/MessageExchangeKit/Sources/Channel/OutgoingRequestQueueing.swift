import Foundation

struct OutgoingRequest<M: MessageExchange.CodableMessage> {
    let requestId: String
    let messages: [M]
    let scaleEncodedPayload: Data
}

extension MessageExchange {
    enum AddToQueueResult {
        case appendedToCurrentRequest
        case queued
        case ignored
    }
}

protocol OutgoingRequestQueueing: AnyObject {
    associatedtype Message: MessageExchange.CodableMessage

    var currentRequest: OutgoingRequest<Message>? { get set }

    func addMessage(
        _ message: Message,
        isChannelActive: Bool
    ) -> Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    >

    func attemptRequestExtensionFromQueue() -> Bool

    func dequeueMessagesForNewRequest() -> OutgoingRequest<Message>?
}

// MARK: - Type Erasure Implementation

final class AnyOutgoingRequestQueue<M: MessageExchange.CodableMessage>: OutgoingRequestQueueing {
    typealias Message = M

    private let currentRequestClosure: () -> OutgoingRequest<Message>?
    private let setCurrentRequestClosure: (OutgoingRequest<Message>?) -> Void
    private let addMessageClosure: (Message, Bool) -> Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    >
    private let dequeueMessagesForNewRequestClosure: () -> OutgoingRequest<Message>?
    private let attemptRequestExtensionClosure: () -> Bool

    init<Queue: OutgoingRequestQueueing>(_ targetQueue: Queue) where Queue.Message == M {
        currentRequestClosure = {
            targetQueue.currentRequest
        }

        setCurrentRequestClosure = { currentRequest in
            targetQueue.currentRequest = currentRequest
        }

        addMessageClosure = { message, isChannelActive in
            targetQueue.addMessage(message, isChannelActive: isChannelActive)
        }

        dequeueMessagesForNewRequestClosure = {
            targetQueue.dequeueMessagesForNewRequest()
        }

        attemptRequestExtensionClosure = {
            targetQueue.attemptRequestExtensionFromQueue()
        }
    }

    var currentRequest: OutgoingRequest<M>? {
        get { currentRequestClosure() }
        set { setCurrentRequestClosure(newValue) }
    }

    func addMessage(
        _ message: Message,
        isChannelActive: Bool
    ) -> Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    > {
        addMessageClosure(message, isChannelActive)
    }

    func dequeueMessagesForNewRequest() -> OutgoingRequest<M>? {
        dequeueMessagesForNewRequestClosure()
    }

    func attemptRequestExtensionFromQueue() -> Bool {
        attemptRequestExtensionClosure()
    }
}
