import Foundation
import WebRTC

final class CallAcceptor: CallCreator {
    private var processingTask: Task<Void, Never>?

    override func clearTasks() {
        super.clearTasks()

        processingTask?.cancel()
        processingTask = nil
    }
}

private extension CallAcceptor {
    private func processCallOffer() {
        logger.debug("Setup signal processing")

        processingTask = Task { [weak self, connectionWrapper, signaling, logger] in
            let incomingSignals = signaling.signals.eraseToAnyAsyncSequence()

            do {
                for try await signal in incomingSignals {
                    logger.debug("Processing new signal")

                    guard !Task.isCancelled else {
                        return
                    }

                    switch signal {
                    case let .offer(sdp):
                        let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdp)
                        try await connectionWrapper.connection.setRemoteDescription(remoteSdp)
                        await self?.drainPendingRemoteCandidates(on: connectionWrapper.connection)
                        logger.debug("Set remote offer successfully")

                        self?.applyLocalTracks()
                        logger.debug("Media tracks set")

                        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

                        let answer = try await connectionWrapper.connection.answer(for: constraints)
                        logger.debug("Local answer created")

                        try await connectionWrapper.connection.setLocalDescription(answer)
                        logger.debug("Local answer set")

                        _ = try await signaling.send(.answer(answer.sdp))

                        self?.negotiated.send(true)
                    case .answer:
                        logger.error("Unexpected answer received by acceptor")
                    case let .candidates(candidates):
                        await self?.handleRemoteCandidates(candidates, on: connectionWrapper.connection)
                    case .closed:
                        await self?.clearPendingRemoteCandidates()
                        logger.debug("Remote closed signal received; stopping offer processing")
                        return
                    }
                }
            } catch {
                self?.negotiated.send(false)
                logger.error("Error signal received: \(error)")
            }
        }
    }
}

extension CallAcceptor: CallCreatorProtocol {
    func setup() {
        logger.debug("Setup initiated")

        processLocalCandidates(from: connectionWrapper)
        processCallOffer()
    }

    func throttle() {
        clearTasks()
    }
}
