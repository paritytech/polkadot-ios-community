import Foundation

public protocol PeerSessionProtocol {
    associatedtype Message: MessageExchange.CodableMessage

    var peer: MessageExchange.Peer { get }
    var sessionId: MessageExchange.SessionId { get }

    func addMessageToQueue(_ message: Message)
}

// MARK: - Type Erasure Implementation

public final class AnyPeerSession<M: MessageExchange.CodableMessage>: PeerSessionProtocol {
    public typealias Message = M

    let peerClosure: () -> MessageExchange.Peer
    let sessionIdClosure: () -> MessageExchange.SessionId

    private let addMessageToQueueClosure: (M) -> Void

    public init<Session: PeerSessionProtocol>(_ targetSession: Session) where Session.Message == M {
        peerClosure = { targetSession.peer }

        sessionIdClosure = { targetSession.sessionId }

        addMessageToQueueClosure = { message in
            targetSession.addMessageToQueue(message)
        }
    }

    public func addMessageToQueue(_ message: Message) {
        addMessageToQueueClosure(message)
    }

    public var peer: MessageExchange.Peer { peerClosure() }

    public var sessionId: MessageExchange.SessionId { sessionIdClosure() }
}
