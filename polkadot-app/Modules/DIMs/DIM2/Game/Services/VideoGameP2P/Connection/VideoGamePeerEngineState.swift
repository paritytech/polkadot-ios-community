import Foundation
import WebRTC

enum VideoGamePeerEngineState {
    case connecting
    case connected(Connected)
    case disconnected

    struct Connected {
        let multiplexedChannel: MultiplexedDataChannel
        let remoteVideoTrack: RTCVideoTrack?
    }
}
