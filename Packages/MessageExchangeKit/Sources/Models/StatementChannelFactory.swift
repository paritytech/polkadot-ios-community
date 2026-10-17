import Foundation
import StatementStore

public protocol StatementChannelMaking {
    /// The single channel carrying the sender's session state on its own topic.
    func createStateChannel(for sessionId: MessageExchange.SessionId) throws -> StatementFixedFieldConvertible

    func createRequestChannel(for sessionId: MessageExchange.SessionId) throws -> StatementFixedFieldConvertible
    func createResponseChannel(for sessionId: MessageExchange.SessionId) throws -> StatementFixedFieldConvertible
    func createPeerRequestChannel(for sessionId: MessageExchange.SessionId) throws -> StatementFixedFieldConvertible
}

public final class ChatStatementChannelFactory {
    public init() {}
}

extension ChatStatementChannelFactory: StatementChannelMaking {
    public func createStateChannel(
        for sessionId: MessageExchange.SessionId
    ) throws -> StatementFixedFieldConvertible {
        try (sessionId.own + Data("state".utf8)).blake2b32WithKey(sessionId.channelKey)
    }

    public func createRequestChannel(for sessionId: MessageExchange
        .SessionId) throws -> StatementFixedFieldConvertible {
        try Data("request".utf8).blake2b32WithKey(sessionId.own)
    }

    public func createResponseChannel(for sessionId: MessageExchange
        .SessionId) throws -> StatementFixedFieldConvertible {
        try Data("response".utf8).blake2b32WithKey(sessionId.own)
    }

    public func createPeerRequestChannel(for sessionId: MessageExchange
        .SessionId) throws -> StatementFixedFieldConvertible {
        try Data("request".utf8).blake2b32WithKey(sessionId.peer)
    }
}
