import Foundation
import WebRTC

final class CallInitiator: CallCreator {
    private var processingTask: Task<Void, Never>?

    override func clearTasks() {
        super.clearTasks()

        processingTask?.cancel()
        processingTask = nil
    }
}

private extension CallInitiator {
    func initiateCall() {
        Task { [weak self, connectionWrapper, signaling, logger] in
            self?.applyLocalTracks()

            do {
                let constrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

                let offer = try await connectionWrapper.connection.offer(for: constrains)

                logger.debug("Offer generated: \(offer.sdp.count)")

                try await connectionWrapper.connection.setLocalDescription(offer)

                logger.debug("Offer set as local description")

                _ = try await signaling.send(.offer(offer.sdp))

                logger.debug("Offer sent to peer")
            } catch {
                self?.negotiated.send(false)
                logger.error("Initiation failed: \(error)")
            }
        }
    }

    private func processCallAnswer() {
        processingTask = Task { [weak self, connectionWrapper, signaling, logger] in
            let incomingSignals = signaling.signals.eraseToAnyAsyncSequence()

            do {
                for try await signal in incomingSignals {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch signal {
                    case .offer:
                        logger.error("Unexpected offer received by initiator")
                    case let .answer(sdp):
                        guard connectionWrapper.connection.signalingState == .haveLocalOffer else {
                            logger.warning(
                                "Ignoring answer in \(connectionWrapper.connection.signalingState) state"
                            )
                            continue
                        }

                        logger.debug("Received answer: \(sdp.count)")

                        let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
                        try await connectionWrapper.connection.setRemoteDescription(remoteSdp)
                        await self?.drainPendingRemoteCandidates(on: connectionWrapper.connection)

                        logger.debug("Set remote answer")

                        self?.negotiated.send(true)
                    case let .candidates(candidates):
                        await self?.handleRemoteCandidates(
                            candidates,
                            on: connectionWrapper.connection
                        )
                    case .closed:
                        await self?.clearPendingRemoteCandidates()
                        logger.debug("Remote closed signal received")
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

extension CallInitiator: CallCreatorProtocol {
    func setup() {
        processLocalCandidates(from: connectionWrapper)
        initiateCall()
        processCallAnswer()
    }

    func throttle() {
        clearTasks()
    }
}
