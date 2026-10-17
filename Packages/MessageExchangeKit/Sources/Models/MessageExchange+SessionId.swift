import Foundation
import SubstrateSdk

public extension MessageExchange {
    struct SessionId: Hashable {
        public let own: Data
        public let peer: Data
        public let ownParameter: Data
        public let peerParameter: Data
        /// The session's shared secret; keys the channel so observers can't recompute it from the public topic.
        public let channelKey: Data
    }
}

// Keeps the channel key out of logs.
extension MessageExchange.SessionId: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "SessionId(own: \(own.toHex()), peer: \(peer.toHex()))"
    }

    public var debugDescription: String {
        description
    }
}
