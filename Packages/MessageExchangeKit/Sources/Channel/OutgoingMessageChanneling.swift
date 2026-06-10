import Foundation
import StatementStore

protocol OutgoingMessageChanneling {
    associatedtype Message: MessageExchange.CodableMessage

    func restoreState(from request: OutgoingRequest<Message>?)
    func setActive(_ isActive: Bool)
    func addMessageToQueue(_ message: Message)
    func handleResponse(_ response: MessageExchange.Response) -> StatementHandlingStatus
}

// MARK: - Type Erasure Implementation

final class AnyOutgoingMessageChannel<M: MessageExchange.CodableMessage>: OutgoingMessageChanneling {
    typealias Message = M

    private let restoreStateClosure: (OutgoingRequest<Message>?) -> Void
    private let addMessageToQueueClosure: (Message) -> Void
    private let setActiveClosure: (Bool) -> Void
    private let handleResponseClosure: (MessageExchange.Response) -> StatementHandlingStatus

    init<Channel: OutgoingMessageChanneling>(_ targetChannel: Channel) where Channel.Message == M {
        restoreStateClosure = { state in
            targetChannel.restoreState(from: state)
        }

        addMessageToQueueClosure = { message in
            targetChannel.addMessageToQueue(message)
        }

        setActiveClosure = { isActive in
            targetChannel.setActive(isActive)
        }

        handleResponseClosure = { response in
            targetChannel.handleResponse(response)
        }
    }

    func restoreState(from request: OutgoingRequest<Message>?) {
        restoreStateClosure(request)
    }

    func addMessageToQueue(_ message: M) {
        addMessageToQueueClosure(message)
    }

    func setActive(_ isActive: Bool) {
        setActiveClosure(isActive)
    }

    func handleResponse(_ response: MessageExchange.Response) -> StatementHandlingStatus {
        handleResponseClosure(response)
    }
}
