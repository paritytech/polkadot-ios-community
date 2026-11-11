import Foundation

struct MessageListMetadata {
    let chatMetadata: ChatMetadata
    let myUsername: String

    var peerMetadata: Chat.PeerMetadata {
        chatMetadata.peerMetadata
    }

    var peerName: String {
        chatMetadata.peerMetadata.name
    }

    func isSeenByPeer(_ message: Chat.LocalMessage) -> Bool {
        message.order > 0 && message.order <= chatMetadata.peerSeenOrder
    }
}
