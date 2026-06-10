import Foundation
import WebRTC
import AsyncExtensions
import AsyncAlgorithms

enum CallCreatorError: Error {
    case negotiationFailed
    case iceConnectionFailed
}

protocol CallCreatorProtocol: AnyObject {
    var multiplexedChannel: MultiplexedDataChannel { get }

    func setup()
    func throttle()
    func subscribeState() -> AnyAsyncSequence<CallCreationState>
}

class CallCreator {
    let connectionWrapper: AsyncPeerConnectionWrapper
    let dataChannelWrapper: AsyncDataChannelWrapper
    let multiplexedChannel: MultiplexedDataChannel
    let localTracks: CallTracks
    let logger: LoggerProtocol

    let signaling: PeerConnectionSignaling

    let negotiated = AsyncCurrentValueSubject<Bool?>(nil)

    private var candidatesTask: Task<Void, Never>?
    private let pendingRemoteCandidates: PendingRemoteCandidatesBuffering

    init(
        connectionWrapper: AsyncPeerConnectionWrapper,
        dataChannelWrapper: AsyncDataChannelWrapper,
        localTracks: CallTracks,
        logger: LoggerProtocol,
        pendingRemoteCandidates: PendingRemoteCandidatesBuffering = PendingRemoteCandidatesBuffer(
            label: "CallCreator"
        )
    ) {
        self.connectionWrapper = connectionWrapper
        self.dataChannelWrapper = dataChannelWrapper
        self.localTracks = localTracks
        self.logger = logger
        self.pendingRemoteCandidates = pendingRemoteCandidates

        multiplexedChannel = MultiplexedDataChannel(
            dataChannelWrapper: dataChannelWrapper,
            logger: logger
        )
        multiplexedChannel.start()

        signaling = DataChannelSignaler(
            multiplexedChannel: multiplexedChannel,
            logger: logger
        )
    }

    deinit {
        logger.debug("Deinited")
    }

    func processLocalCandidates(from wrapper: AsyncPeerConnectionWrapper) {
        candidatesTask = Task { [signaling, logger] in
            let sequence = wrapper.candidates.eraseToAnyAsyncSequence()

            do {
                for try await candidateOp in sequence {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch candidateOp {
                    case let .add(iceCandidate):
                        let signalCandidate = PeerConnectionCandidate(iceCandidate: iceCandidate)
                        _ = try await signaling.send(.candidates([signalCandidate]))
                        logger.debug("Sent new candidate: \(signalCandidate)")
                    case .remove:
                        // unsupported yet
                        logger.warning("Candidate removed but this not yet supported")
                    }
                }

                logger.debug("Candidates processing completed")
            } catch {
                logger.error("Candidates task failed")
            }
        }
    }

    func handleRemoteCandidates(
        _ candidates: [PeerConnectionCandidate],
        on connection: RTCPeerConnection
    ) async {
        guard connection.remoteDescription != nil else {
            await bufferRemoteCandidates(candidates)
            return
        }

        await applyRemoteCandidates(candidates, on: connection)
    }

    func drainPendingRemoteCandidates(on connection: RTCPeerConnection) async {
        guard connection.remoteDescription != nil else {
            return
        }

        let candidates = await pendingRemoteCandidates.takeAll()
        guard !candidates.isEmpty else { return }

        await applyRemoteCandidates(candidates, on: connection)
    }

    func clearPendingRemoteCandidates() async {
        await pendingRemoteCandidates.clear()
    }

    func applyLocalTracks() {
        if let audioTrack = localTracks.audioTrack {
            connectionWrapper.connection.add(audioTrack, streamIds: ["stream0"])
        }

        if let videoTrack = localTracks.videoTrack {
            connectionWrapper.connection.add(videoTrack, streamIds: ["stream0"])
        } else {
            // video is not enabled but still do negotiation for better UX when a user enables it

            let videoTranceiver = connectionWrapper.connection.addTransceiver(
                of: .video,
                init: .init()
            )

            videoTranceiver?.setDirection(.recvOnly, error: .none)
        }
    }

    func clearTasks() {
        candidatesTask?.cancel()
        candidatesTask = nil
    }
}

private extension CallCreator {
    func bufferRemoteCandidates(_ candidates: [PeerConnectionCandidate]) async {
        guard !candidates.isEmpty else { return }

        await pendingRemoteCandidates.append(candidates)
    }

    func applyRemoteCandidates(
        _ candidates: [PeerConnectionCandidate],
        on connection: RTCPeerConnection
    ) async {
        for candidate in candidates {
            do {
                try await connection.add(candidate.toRTCIceCandidate())
                logger.debug("Applied candidate: \(candidate)")
            } catch {
                logger.error("Can't process candidate: \(candidate)")
            }
        }
    }
}

extension CallCreator {
    func subscribeState() -> AnyAsyncSequence<CallCreationState> {
        let negotiatedStream = negotiated.eraseToAnyAsyncSequence()
        let signalingStateStream = connectionWrapper.signalingState.eraseToAnyAsyncSequence()
        let iceStateStream = connectionWrapper.iceConnectionState.eraseToAnyAsyncSequence()
        let tracksStream = connectionWrapper
            .rtpReceivers
            .map { rtpReceivers in
                rtpReceivers.reduce(CallTracks()) { $0.replacingFromRTPReceiver($1) }
            }
            .eraseToAnyAsyncSequence()

        return combineLatest(
            combineLatest(signalingStateStream, iceStateStream),
            combineLatest(negotiatedStream, tracksStream)
        ).map { connectionStates, negotiationStates in
            let (signalingState, iceState) = connectionStates
            let (negotiated, tracks) = negotiationStates

            if let iceState, iceState.isTerminal {
                let error = CallCreatorError(iceState: iceState)
                return CallCreationState.closed(error)
            }

            guard negotiated != false else {
                return CallCreationState.closed(CallCreatorError.negotiationFailed)
            }

            guard signalingState == .stable, negotiated == true else {
                return CallCreationState.creating
            }

            return CallCreationState.ready(tracks)
        }
        .eraseToAnyAsyncSequence()
    }
}

extension CallCreatorError {
    init?(iceState: RTCIceConnectionState) {
        switch iceState {
        case .failed:
            self = .iceConnectionFailed
        default:
            return nil
        }
    }
}
