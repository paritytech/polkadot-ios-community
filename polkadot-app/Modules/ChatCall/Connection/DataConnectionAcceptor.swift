import Foundation
import WebRTC
import AsyncExtensions
import AsyncAlgorithms

final class DataConnectionAcceptor: DataConnectionCreator {
    private var signalingTask: Task<Void, Never>?

    override func clearTasks() {
        super.clearTasks()

        signalingTask?.cancel()
        signalingTask = nil
    }
}

private extension DataConnectionAcceptor {
    func processSignaling(on connection: RTCPeerConnection) {
        signalingTask = Task { [weak self, context, logger] in
            let incomingSignals = await context.signals

            do {
                for try await signal in incomingSignals {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch signal {
                    case let .offer(sdp):
                        logger.debug("Offer received: \(sdp.count)")

                        // Create remote description
                        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
                        try await connection.setRemoteDescription(remoteSdp)
                        await self?.drainPendingRemoteCandidates(on: connection)

                        logger.debug("Set remote offer")

                        // Create initial answer (data channel only)
                        let constraints = RTCMediaConstraints(
                            mandatoryConstraints: nil,
                            optionalConstraints: nil
                        )
                        let answer = try await connection.answer(for: constraints)
                        try await connection.setLocalDescription(answer)

                        logger.debug("Set local answer")

                        await context.sendSignalAndFlushBuffer(.answer(answer.sdp))
                        await context.startAutoflush()

                        logger.debug("Sent answer \(answer.sdp.count)")

                    case .answer:
                        logger.error("Unexpected answer received by acceptor")

                    case let .candidates(sdpList):
                        await self?.handleRemoteCandidates(sdpList, on: connection)

                    case .closed:
                        await self?.clearPendingRemoteCandidates()
                        logger.debug("Remote closed signal received")
                        return
                    }
                }

                logger.debug("Signaling processing completed")
            } catch {
                logger.error("No signal received")
            }
        }
    }

    func createStateSequence(
        for connectionWrapper: AsyncPeerConnectionWrapper
    ) -> AnyAsyncSequence<PeerDataConnectionState> {
        let signalingState = connectionWrapper.signalingState.eraseToAnyAsyncSequence()
        let openedDataChannels = connectionWrapper.openedDataChannels.eraseToAnyAsyncSequence()

        return combineLatest(signalingState, openedDataChannels)
            .map { [logger] optSignalingState, dataChannels in
                logger.debug("Signaling: \(String(describing: optSignalingState))")
                logger.debug("Data channels: \(dataChannels.count)")

                switch optSignalingState {
                case .stable:
                    if let dataChannelWrapper = dataChannels.first {
                        let model = PeerDataConnectionState.Connected(
                            connection: connectionWrapper,
                            dataChannel: dataChannelWrapper
                        )

                        return .connected(model)
                    } else {
                        return .connecting
                    }
                case .closed:
                    return .disconnected
                default:
                    return .connecting
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

extension DataConnectionAcceptor: DataConnectionCreating {
    func connect() async throws -> AnyAsyncSequence<PeerDataConnectionState> {
        let connectionWrapper = try await setupConnection()

        processSignaling(on: connectionWrapper.connection)
        processLocalCandidates(from: connectionWrapper)

        return createStateSequence(for: connectionWrapper)
    }

    func throttle() {
        clearTasks()
    }
}
