import Foundation

struct MessageListMetadata {
    let chatMetadata: ChatMetadata
    let myUsername: String
    var isIncomingRequestCancelled = false

    var peerMetadata: Chat.PeerMetadata {
        chatMetadata.peerMetadata
    }

    var peerName: String {
        chatMetadata.peerMetadata.name
    }
}
