import Foundation
import WebRTC
import AsyncExtensions
import AsyncAlgorithms

enum DataConnectionInitiatorError: Error {
    case dataChannelCreationFailed
}

final class DataConnectionInitiator: DataConnectionCreator {
    private var dataChannelWrapper: AsyncDataChannelWrapper?

    let purpose: String

    private var signalingTask: Task<Void, Never>?

    init(
        signaling: PeerConnectionSignaling,
        peerConnectionFactory: RTCPeerConnectionFactory,
        configFactory: WebRTCConfigMaking,
        purpose: String,
        logger: LoggerProtocol
    ) {
        self.purpose = purpose

        super.init(
            signaling: signaling,
            peerConnectionFactory: peerConnectionFactory,
            configFactory: configFactory,
            logger: logger
        )
    }

    override func clearTasks() {
        super.clearTasks()

        signalingTask?.cancel()
        signalingTask = nil
    }
}

private extension DataConnectionInitiator {
    func setupDataChannel(on connection: RTCPeerConnection, purpose: String) throws -> AsyncDataChannelWrapper {
        guard let dataChannel = connection.dataChannel(
            forLabel: purpose,
            configuration: configFactory.makeDataChannelConfiguration()
        ) else {
            throw DataConnectionInitiatorError.dataChannelCreationFailed
        }

        let wrapper = AsyncDataChannelWrapper(dataChannel: dataChannel, logger: logger)
        wrapper.setup()

        dataChannelWrapper = wrapper

        return wrapper
    }

    func processSignaling(on connection: RTCPeerConnection) {
        signalingTask = Task { [weak self, context, logger] in
            let incomingSignals = await context.signals

            do {
                for try await signal in incomingSignals {
                    guard !Task.isCancelled else {
                        return
                    }

                    do {
                        switch signal {
                        case .offer:
                            logger.error("Unexpected offer received by initiator")
                        case let .answer(sdp):
                            guard connection.signalingState == .haveLocalOffer else {
                                logger.warning(
                                    "Ignoring answer in \(connection.signalingState) state"
                                )
                                continue
                            }

                            logger.debug("Received answer: \(sdp.count)")

                            let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdp)
                            try await connection.setRemoteDescription(remoteSdp)
                            await self?.drainPendingRemoteCandidates(on: connection)

                            logger.debug("Set remote answer")

                            // once answer received auto send new candidates
                            await context.startAutoflush()
                        case let .candidates(sdpList):
                            await self?.handleRemoteCandidates(sdpList, on: connection)
                        case .closed:
                            await self?.clearPendingRemoteCandidates()
                            logger.debug("Remote closed signal received")
                            return
                        }
                    } catch {
                        logger.error("Signal processing failed: \(error)")
                    }
                }

                logger.debug("Signaling task finished")
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger.error("Signal task failed: \(error)")
            }
        }
    }

    func initiateChannelEstablishment(using connection: RTCPeerConnection) {
        Task { [context, logger] in
            // Create offer with only data channel (no media tracks yet)
            // This keeps the initial SDP small
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )

            guard !Task.isCancelled else {
                return
            }

            let offer = try await connection.offer(for: constraints)

            guard !Task.isCancelled else {
                return
            }

            try await connection.setLocalDescription(offer)

            logger.debug("Set local offer")

            guard !Task.isCancelled else {
                return
            }

            // send offer and candidates discovered fast enough
            // slow candidates will be sent once we got an answer
            await context.sendSignalAndFlushBuffer(.offer(offer.sdp))

            logger.debug("Sent offer: \(offer.sdp.count)")
        }
    }

    func createStateSequence(
        for connectionWrapper: AsyncPeerConnectionWrapper,
        dataWrapper: AsyncDataChannelWrapper
    ) -> AnyAsyncSequence<PeerDataConnectionState> {
        let signalingState = connectionWrapper.signalingState.eraseToAnyAsyncSequence()
        let dataChannelState = dataWrapper.state.eraseToAnyAsyncSequence()

        return combineLatest(signalingState, dataChannelState)
            .map { [logger] optSignalingState, dataChannelState in
                logger.debug("Signaling: \(String(describing: optSignalingState))")
                logger.debug("Data channel state: \(dataChannelState)")

                switch (optSignalingState, dataChannelState) {
                case (.some(.stable), .open):
                    let model = PeerDataConnectionState.Connected(
                        connection: connectionWrapper,
                        dataChannel: dataWrapper
                    )

                    return .connected(model)
                case (.some(.closed), _):
                    return .disconnected
                case (_, .closed):
                    return .disconnected
                case (.some(.haveRemoteOffer), _):
                    return .connecting
                case (.some(.haveRemotePrAnswer), _):
                    return .connecting
                case (.some(.stable), _):
                    return .connecting
                default:
                    return .waiting
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

extension DataConnectionInitiator: DataConnectionCreating {
    func connect() async throws -> AnyAsyncSequence<PeerDataConnectionState> {
        let connectionWrapper = try await setupConnection()
        let dataChannelWrapper = try setupDataChannel(
            on: connectionWrapper.connection,
            purpose: purpose
        )

        processSignaling(on: connectionWrapper.connection)
        processLocalCandidates(from: connectionWrapper)

        initiateChannelEstablishment(using: connectionWrapper.connection)

        return createStateSequence(for: connectionWrapper, dataWrapper: dataChannelWrapper)
    }

    func throttle() {
        clearTasks()
    }
}
