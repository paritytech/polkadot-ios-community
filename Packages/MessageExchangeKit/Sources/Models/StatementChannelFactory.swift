import Foundation
import StatementStore

public protocol StatementChannelMaking {
    /// The single channel carrying the sender's session state on its own topic.
    func createStateChannel(for sessionId: MessageExchange.SessionId) throws -> StatementFixedFieldConvertible
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
}
