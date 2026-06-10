import Foundation

public protocol PeerSessionManaging {
    associatedtype Message: MessageExchange.CodableMessage

    func updateSessions(_ requests: Set<MessageExchange.SessionRequest>)
    func addMessageToQueue(_ message: Message, for peer: MessageExchange.Peer)
}

// MARK: - Type Erasure Implementation

public final class AnyPeerSessionManager<M: MessageExchange.CodableMessage>: PeerSessionManaging {
    public typealias Message = M

    private let updateSessionsClosure: (Set<MessageExchange.SessionRequest>) -> Void
    private let addMessageToQueueClosure: (M, MessageExchange.Peer) -> Void

    public init<P: PeerSessionManaging>(_ targetManager: P) where P.Message == M {
        updateSessionsClosure = { requests in
            targetManager.updateSessions(requests)
        }

        addMessageToQueueClosure = { message, peer in
            targetManager.addMessageToQueue(message, for: peer)
        }
    }

    public func updateSessions(_ requests: Set<MessageExchange.SessionRequest>) {
        updateSessionsClosure(requests)
    }

    public func addMessageToQueue(_ message: Message, for peer: MessageExchange.Peer) {
        addMessageToQueueClosure(message, peer)
    }
}
