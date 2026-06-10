import Foundation
import AsyncExtensions
import WebRTC

enum DataConnectionCreatorError: Error {
    case connectionCreationFailed
}

protocol DataConnectionCreating {
    var sentSignals: AnyAsyncSequence<(PeerConnectionSignal, PeerConnectionSignalStateObserving)> { get }
    func connect() async throws -> AnyAsyncSequence<PeerDataConnectionState>
    func throttle()
}

class DataConnectionCreator {
    let logger: LoggerProtocol

    let peerConnectionFactory: RTCPeerConnectionFactory
    let configFactory: WebRTCConfigMaking
    let context: DataConnectionContext

    var sentSignals: AnyAsyncSequence<(PeerConnectionSignal, PeerConnectionSignalStateObserving)> {
        context.sentSignals.eraseToAnyAsyncSequence()
    }

    private var connectionWrapper: AsyncPeerConnectionWrapper?
    private var candidatesTask: Task<Void, Never>?
    private let pendingRemoteCandidates: PendingRemoteCandidatesBuffering

    init(
        signaling: PeerConnectionSignaling,
        peerConnectionFactory: RTCPeerConnectionFactory,
        configFactory: WebRTCConfigMaking,
        logger: LoggerProtocol,
        pendingRemoteCandidates: PendingRemoteCandidatesBuffering = PendingRemoteCandidatesBuffer(
            label: "DataConnectionCreator"
        )
    ) {
        context = DataConnectionContext(
            signaler: signaling,
            logger: logger
        )

        self.peerConnectionFactory = peerConnectionFactory
        self.configFactory = configFactory
        self.logger = logger
        self.pendingRemoteCandidates = pendingRemoteCandidates
    }

    deinit {
        clearTasks()
        logger.debug("Deinited")
    }

    func setupConnection() async throws -> AsyncPeerConnectionWrapper {
        RTCSetMinDebugLogLevel(.none)

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        let configuration = try await configFactory.makeConnectionConfiguration()

        let optPeerConnection = peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: nil
        )

        guard let peerConnection = optPeerConnection else {
            throw DataConnectionCreatorError.connectionCreationFailed
        }

        let connectionWrapper = AsyncPeerConnectionWrapper(
            connection: peerConnection,
            logger: logger
        )

        connectionWrapper.setup()

        self.connectionWrapper = connectionWrapper

        return connectionWrapper
    }

    func processLocalCandidates(from wrapper: AsyncPeerConnectionWrapper) {
        candidatesTask = Task { [context, logger] in
            let sequence = wrapper.candidates.eraseToAnyAsyncSequence()

            do {
                for try await candidateOp in sequence {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch candidateOp {
                    case let .add(iceCandidate):
                        let signalCandidate = PeerConnectionCandidate(iceCandidate: iceCandidate)
                        await context.append(.candidates([signalCandidate]))
                        logger.debug("Sent new candidate: \(iceCandidate.sdp)")
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

    func clearTasks() {
        candidatesTask?.cancel()
        candidatesTask = nil
    }
}

private extension DataConnectionCreator {
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
