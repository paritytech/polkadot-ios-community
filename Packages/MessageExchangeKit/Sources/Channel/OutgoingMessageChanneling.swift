import Foundation
import StatementStore

protocol OutgoingMessageChanneling {
    associatedtype Message: MessageExchange.CodableMessage

    func restoreState(from requests: [PeerSessionRoute: OutgoingRequest<Message>])
    func setActive(_ isActive: Bool)
    func addMessagesToQueue(_ messages: [Message])
    func handleResponse(
        _ response: MessageExchange.Response,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus
}

// MARK: - Type Erasure Implementation

final class AnyOutgoingMessageChannel<M: MessageExchange.CodableMessage>: OutgoingMessageChanneling {
    typealias Message = M

    private let restoreStateClosure: ([PeerSessionRoute: OutgoingRequest<Message>]) -> Void
    private let addMessagesToQueueClosure: ([Message]) -> Void
    private let setActiveClosure: (Bool) -> Void
    private let handleResponseClosure: (MessageExchange.Response, PeerSessionRoute) -> StatementHandlingStatus

    init<Channel: OutgoingMessageChanneling>(_ targetChannel: Channel) where Channel.Message == M {
        restoreStateClosure = { requests in
            targetChannel.restoreState(from: requests)
        }

        addMessagesToQueueClosure = { messages in
            targetChannel.addMessagesToQueue(messages)
        }

        setActiveClosure = { isActive in
            targetChannel.setActive(isActive)
        }

        handleResponseClosure = { response, route in
            targetChannel.handleResponse(response, route: route)
        }
    }

    func restoreState(from requests: [PeerSessionRoute: OutgoingRequest<Message>]) {
        restoreStateClosure(requests)
    }

    func addMessagesToQueue(_ messages: [M]) {
        addMessagesToQueueClosure(messages)
    }

    func setActive(_ isActive: Bool) {
        setActiveClosure(isActive)
    }

    func handleResponse(
        _ response: MessageExchange.Response,
        route: PeerSessionRoute
    ) -> StatementHandlingStatus {
        handleResponseClosure(response, route)
    }
}
