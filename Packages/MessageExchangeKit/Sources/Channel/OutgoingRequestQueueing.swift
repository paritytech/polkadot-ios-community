import Foundation

struct OutgoingRequest<M: MessageExchange.CodableMessage> {
    let requestId: String
    let messages: [M]
    let route: PeerSessionRoute
}

extension StatementDataCoding {
    /// Encodes a request inside a state that also carries an ack, the largest shape it is published in.
    func encodeForSizing<M: MessageExchange.CodableMessage>(
        requestId: String,
        messages: [M],
        route: PeerSessionRoute
    ) throws -> Data {
        let state = MessageExchange.SessionState(
            response: MessageExchange.Response(requestId: UUID().uuidString, responseCode: .failure(.max)),
            request: MessageExchange.Request(requestId: requestId, messages: messages)
        )

        return try encodeToScaleEncodedPayload(StatementData<M>.state(state), route: route)
    }
}

extension MessageExchange {
    enum AddToQueueResult: Equatable {
        case appendedToCurrentRequest(route: PeerSessionRoute)
        case queued
        case ignored
    }
}

protocol OutgoingRequestQueueing: AnyObject {
    associatedtype Message: MessageExchange.CodableMessage

    var currentRequests: [PeerSessionRoute: OutgoingRequest<Message>] { get set }

    /// Adds messages to the queue, preserving order. Returns one result per
    /// message in the same order; per-message size validation and duplicate
    /// detection are applied independently.
    func addMessages(
        _ messages: [Message],
        isChannelActive: Bool
    ) -> [Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    >]

    func attemptRequestExtensionFromQueue() -> Set<PeerSessionRoute>

    func dequeueMessagesForNewRequest() -> OutgoingRequest<Message>?

    func reset(route: PeerSessionRoute)
}

// MARK: - Type Erasure Implementation

final class AnyOutgoingRequestQueue<M: MessageExchange.CodableMessage>: OutgoingRequestQueueing {
    typealias Message = M

    private let currentRequestsClosure: () -> [PeerSessionRoute: OutgoingRequest<Message>]
    private let setCurrentRequestsClosure: ([PeerSessionRoute: OutgoingRequest<Message>]) -> Void
    private let addMessagesClosure: ([Message], Bool) -> [Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    >]
    private let dequeueMessagesForNewRequestClosure: () -> OutgoingRequest<Message>?
    private let attemptRequestExtensionClosure: () -> Set<PeerSessionRoute>
    private let resetClosure: (PeerSessionRoute) -> Void

    init<Queue: OutgoingRequestQueueing>(_ targetQueue: Queue) where Queue.Message == M {
        currentRequestsClosure = {
            targetQueue.currentRequests
        }

        setCurrentRequestsClosure = { currentRequests in
            targetQueue.currentRequests = currentRequests
        }

        addMessagesClosure = { messages, isChannelActive in
            targetQueue.addMessages(messages, isChannelActive: isChannelActive)
        }

        dequeueMessagesForNewRequestClosure = {
            targetQueue.dequeueMessagesForNewRequest()
        }

        attemptRequestExtensionClosure = {
            targetQueue.attemptRequestExtensionFromQueue()
        }

        resetClosure = { route in
            targetQueue.reset(route: route)
        }
    }

    var currentRequests: [PeerSessionRoute: OutgoingRequest<M>] {
        get { currentRequestsClosure() }
        set { setCurrentRequestsClosure(newValue) }
    }

    func addMessages(
        _ messages: [Message],
        isChannelActive: Bool
    ) -> [Result<
        MessageExchange.AddToQueueResult,
        MessageExchange.AddToQueueError
    >] {
        addMessagesClosure(messages, isChannelActive)
    }

    func dequeueMessagesForNewRequest() -> OutgoingRequest<M>? {
        dequeueMessagesForNewRequestClosure()
    }

    func attemptRequestExtensionFromQueue() -> Set<PeerSessionRoute> {
        attemptRequestExtensionClosure()
    }

    func reset(route: PeerSessionRoute) {
        resetClosure(route)
    }
}
