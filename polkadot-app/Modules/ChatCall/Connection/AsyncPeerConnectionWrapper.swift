import Foundation
import WebRTC
import AsyncExtensions

final class AsyncPeerConnectionWrapper: NSObject {
    enum CandidateState {
        case add(RTCIceCandidate)
        case remove([RTCIceCandidate])
    }

    let connection: RTCPeerConnection
    let logger: LoggerProtocol

    private let connectionDelegateQueue = DispatchQueue(label: "io.async.peer.connection.wrapper.queue")

    let signalingState: AsyncCurrentValueSubject<RTCSignalingState?> = .init(nil)
    let rtpReceivers: AsyncCurrentValueSubject<Set<RTCRtpReceiver>> = .init([])
    let shouldNegotiateState: AsyncCurrentValueSubject<Bool> = .init(false)
    let openedDataChannels: AsyncCurrentValueSubject<[AsyncDataChannelWrapper]> = .init([])
    let iceConnectionState: AsyncCurrentValueSubject<RTCIceConnectionState?> = .init(nil)
    let iceGatheringState: AsyncCurrentValueSubject<RTCIceGatheringState?> = .init(nil)
    let candidates: AsyncPassthroughSubject<CandidateState> = .init()

    init(connection: RTCPeerConnection, logger: LoggerProtocol) {
        self.connection = connection
        self.logger = logger
    }

    func setup() {
        connection.delegate = self
    }

    deinit {
        logger.debug("Deinited")
    }
}

extension AsyncPeerConnectionWrapper: RTCPeerConnectionDelegate {
    // legacy api still required but we handle stream as rtpReceivers
    func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}

    func peerConnection(_: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.shared.debug("Did change signaling state: \(stateChanged)")

        connectionDelegateQueue.async {
            self.signalingState.send(stateChanged)
        }
    }

    func peerConnectionShouldNegotiate(_: RTCPeerConnection) {
        connectionDelegateQueue.async {
            self.shouldNegotiateState.send(true)
        }
    }

    func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams _: [RTCMediaStream]) {
        logger.debug("Did add rtp receiver")

        connectionDelegateQueue.async {
            var currentValue = self.rtpReceivers.value
            currentValue.insert(rtpReceiver)
            self.rtpReceivers.send(currentValue)
        }
    }

    func peerConnection(_: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        logger.debug("Did remove rtp receiver")

        connectionDelegateQueue.async {
            var currentValue = self.rtpReceivers.value
            currentValue.remove(rtpReceiver)
            self.rtpReceivers.send(currentValue)
        }
    }

    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.debug("Did change state ice connection state: \(newState)")

        connectionDelegateQueue.async {
            self.iceConnectionState.send(newState)
        }
    }

    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.debug("Did change state ice gathering state: \(newState)")

        connectionDelegateQueue.async {
            self.iceGatheringState.send(newState)
        }
    }

    func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        logger.debug("Did generate candidate")

        connectionDelegateQueue.async {
            self.candidates.send(.add(candidate))
        }
    }

    func peerConnection(_: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.debug("Did remove candidates: \(candidates.count)")

        connectionDelegateQueue.async {
            self.candidates.send(.remove(candidates))
        }
    }

    func peerConnection(_: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.debug("Did open data channel")

        let wrapper = AsyncDataChannelWrapper(dataChannel: dataChannel, logger: logger)
        wrapper.setup()

        connectionDelegateQueue.async {
            var currentValue = self.openedDataChannels.value
            currentValue.append(wrapper)
            self.openedDataChannels.send(currentValue)
        }
    }
}
