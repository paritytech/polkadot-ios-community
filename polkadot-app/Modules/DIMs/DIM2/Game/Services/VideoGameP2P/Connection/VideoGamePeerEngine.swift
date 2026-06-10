import Foundation
import Foundation_iOS
import WebRTC
import AsyncExtensions
import MessageExchangeKit
import SubstrateSdk
import Individuality

/// Manages a single WebRTC connection to one remote player.
///
/// Responsibilities:
/// - Determines initiator/acceptor role via unsigned byte comparison of account IDs.
/// - Establishes a data channel using `DataConnectionInitiator`/`DataConnectionAcceptor`.
/// - Creates a `MultiplexedDataChannel` from the established data channel.
/// - Performs media upgrade using `CallInitiator`/`CallAcceptor`.
/// - Handles reconnection via `reconnected` signaling messages.
/// - Persists offer IDs via `ConnectionAttemptTracker`.
final class VideoGamePeerEngine: TypeErasedDelegateStoring {
    private let localAccountId: AccountId
    private let remoteAccountId: AccountId
    private let gameIndex: GamePallet.GameIndex
    private let localVideoTrack: RTCVideoTrack?
    private let sessionFactory: VideoGameSessionMaking
    private let attemptTracker: ConnectionAttemptTracking
    private let logger: LoggerProtocol

    private let stateSubject = AsyncCurrentValueSubject<VideoGamePeerEngineState>(.connecting)
    private let mutex = NSLock()
    private var connectionTask: Task<Void, Never>?
    private var reconnectionTask: Task<Void, Never>?

    private var signalingSession: VideoGameSignalingSession?
    private var dataConnectionCreator: DataConnectionCreating?
    private var callCreator: CallCreatorProtocol?
    private var connectionWrapper: AsyncPeerConnectionWrapper?

    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let configFactory: WebRTCConfigMaking

    /// Short identifier for the remote peer, used in log messages.
    private var peerTag: String {
        "[\(remoteAccountId.toHex().prefix(8))]"
    }

    private func logDebug(_ message: String) {
        logger.debug("\(peerTag) \(message)")
    }

    private func logError(_ message: String) {
        logger.error("\(peerTag) \(message)")
    }

    private func logDebug(_ message: String, error: (some Error)?) {
        logDebug(message)

        if let error {
            logError("\(message) error: \(error)")
        }
    }

    var isInitiator: Bool {
        localAccountId.precedes(remoteAccountId)
    }

    init(
        localAccountId: AccountId,
        remoteAccountId: AccountId,
        gameIndex: GamePallet.GameIndex,
        localVideoTrack: RTCVideoTrack?,
        sessionFactory: VideoGameSessionMaking,
        attemptTracker: ConnectionAttemptTracking,
        configFactory: WebRTCConfigMaking,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localAccountId = localAccountId
        self.remoteAccountId = remoteAccountId
        self.gameIndex = gameIndex
        self.localVideoTrack = localVideoTrack
        self.sessionFactory = sessionFactory
        self.attemptTracker = attemptTracker
        self.configFactory = configFactory
        self.logger = logger

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        logDebug("Initialized")
    }

    deinit {
        logDebug("Deinit")
    }

    // MARK: - Public API

    func stateStream() -> AnyAsyncSequence<VideoGamePeerEngineState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    func start() {
        let task = Task { [weak self] in
            guard let self else { return }
            await performConnection()
        }
        mutex.withLock { connectionTask = task }
    }

    func dispose() {
        let (connTask, reconTask, call, dataConn, connection) = mutex.withLock {
            let snapshot = (connectionTask, reconnectionTask, callCreator, dataConnectionCreator, connectionWrapper)
            connectionTask = nil
            reconnectionTask = nil
            callCreator = nil
            dataConnectionCreator = nil
            connectionWrapper = nil
            signalingSession = nil
            return snapshot
        }

        connTask?.cancel()
        reconTask?.cancel()
        call?.throttle()
        dataConn?.throttle()

        Task {
            connection?.connection.close()
        }
    }

    func clearPersistedOfferId() {
        logDebug("Clearing persisted offer id")
        attemptTracker.clearOfferId(gameIndex: gameIndex, remoteAccountId: remoteAccountId)
    }
}

// MARK: - PeerSessionDelegate

extension VideoGamePeerEngine: PeerSessionDelegate {
    typealias Message = OpaqueVideoGameSignalingEnvelope

    func peerSession(
        _: any PeerSessionProtocol,
        didUpdateState state: PeerSessionState
    ) {
        logDebug("Peer session state: \(state)")
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didInitializeWithOutgoingMessages messages: [OpaqueVideoGameSignalingEnvelope]
    ) {
        logDebug("Peer session initialized with \(messages.count) pending messages")
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldResetAfter error: MessageExchange.InitializationError
    ) -> Bool {
        logDebug("Session going to reset after \(error)")
        return true
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didFinishAddingMessageToQueue _: OpaqueVideoGameSignalingEnvelope,
        withError error: MessageExchange.AddToQueueError?
    ) {
        logDebug("Did add envelope to queue", error: error)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didPostMessages messages: [OpaqueVideoGameSignalingEnvelope],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        logDebug("Did post \(messages.count) envelopes", error: error)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didDeliverMessages messages: [OpaqueVideoGameSignalingEnvelope],
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        logDebug("Did deliver \(messages.count) envelopes", error: error)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        didReceiveMessages messages: [OpaqueVideoGameSignalingEnvelope],
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        logDebug("Did receive \(messages.count) envelopes")
        let session = mutex.withLock { signalingSession }
        session?.handleIncomingEnvelopes(messages.map(\.message))
        respondHandler(.success)
    }

    func peerSessionDidReceiveMessagesError(
        _: any PeerSessionProtocol,
        respondHandler: @escaping (MessageExchange.ResponseCode) -> Void
    ) {
        logError("Did receive envelope error")
        respondHandler(.success)
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldIgnoreStatementAfter _: MessageExchange.IncomingMessageError
    ) -> Bool {
        logDebug("Ignoring statement")
        return true
    }

    func peerSession(
        _: any PeerSessionProtocol,
        shouldReinitializeAfterSubmitError error: Error
    ) -> Bool {
        logDebug("Submit error: \(error)")
        return true
    }
}

// MARK: - Connection Logic

private extension VideoGamePeerEngine {
    func performConnection() async {
        do {
            // 1. Create signaling session via factory
            let session = try await sessionFactory.makeSession(
                gameIndex: gameIndex,
                peerAccountId: remoteAccountId,
                delegate: AnyPeerSessionDelegate(self)
            )

            guard !Task.isCancelled else { return }

            mutex.withLock { signalingSession = session }

            // 2. Handle reconnection: if we have a persisted offer ID, send reconnected message
            if let lastOfferId = attemptTracker.getLastOfferId(
                gameIndex: gameIndex,
                remoteAccountId: remoteAccountId
            ) {
                session.sendReconnected(lastOfferId)
                logDebug("Sent reconnected with offer ID: \(lastOfferId)")
            }

            // 3. Subscribe to reconnection signals from remote peer
            subscribeToReconnection(session: session)

            // 4. Establish data channel (Phase 1)
            logDebug("isInitiator = \(isInitiator)")
            let role: CallRole = isInitiator ? .initiator : .acceptor

            let dataCreator = makeDataConnectionCreator(signaling: session, role: role)
            mutex.withLock { dataConnectionCreator = dataCreator }

            guard let stateSequence = await createConnection(with: dataCreator) else {
                logError("Data channel creation failed")
                stateSubject.send(.disconnected)
                return
            }

            logDebug("Establishing data channel...")
            stateSubject.send(.connecting)

            guard let dataConnected = await waitDataChannelConnected(from: stateSequence) else {
                stateSubject.send(.disconnected)
                return
            }

            guard !Task.isCancelled else { return }

            logDebug("Data channel established")

            // Persist offer ID per spec Section 5.2 asymmetric timing
            if let offerId = session.activeOfferId {
                attemptTracker.persistOfferId(
                    offerId,
                    gameIndex: gameIndex,
                    remoteAccountId: remoteAccountId
                )
            }

            // Throttle the data connection creator (it's done its job)
            dataCreator.throttle()
            mutex.withLock { dataConnectionCreator = nil }

            // 5. Upgrade to media (Phase 2) — video-only
            let localTracks = createVideoOnlyTracks()
            let mediaCreator = makeCallCreator(
                for: dataConnected,
                tracks: localTracks,
                role: role
            )

            mutex.withLock {
                connectionWrapper = dataConnected.connection
                callCreator = mediaCreator
            }

            guard !Task.isCancelled else { return }

            mediaCreator.setup()

            // 6. Use the multiplexed channel created by CallCreator
            // (CallCreator creates its own MultiplexedDataChannel + DataChannelSignaler
            // for renegotiation signaling — creating a second one would steal messages)
            let multiplexedChannel = mediaCreator.multiplexedChannel

            // 7. Report state from media upgrade
            await reportMediaState(
                callCreator: mediaCreator,
                multiplexedChannel: multiplexedChannel
            )

            logDebug("Connection completed")
        } catch {
            logError("Connection failed: \(error)")
            stateSubject.send(.disconnected)
        }
    }

    // MARK: - Data Channel Phase

    func makeDataConnectionCreator(
        signaling: PeerConnectionSignaling,
        role: CallRole
    ) -> DataConnectionCreating {
        switch role {
        case .initiator:
            DataConnectionInitiator(
                signaling: signaling,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                purpose: "video_game",
                logger: logger
            )
        case .acceptor:
            DataConnectionAcceptor(
                signaling: signaling,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                logger: logger
            )
        }
    }

    func createConnection(
        with dataCreator: DataConnectionCreating
    ) async -> AnyAsyncSequence<PeerDataConnectionState>? {
        do {
            return try await dataCreator.connect()
        } catch {
            logError("Failed to create connection: \(error)")
            return nil
        }
    }

    func waitDataChannelConnected(
        from sequence: AnyAsyncSequence<PeerDataConnectionState>
    ) async -> PeerDataConnectionState.Connected? {
        do {
            for try await state in sequence {
                switch state {
                case .waiting,
                     .connecting:
                    continue
                case let .connected(model):
                    return model
                case .disconnected:
                    return nil
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Media Upgrade Phase

    func createVideoOnlyTracks() -> CallTracks {
        if let localVideoTrack {
            return CallTracks(videoTrack: localVideoTrack)
        }

        // Fallback: create a track without a capturer (no frames will be sent)
        let videoSource = peerConnectionFactory.videoSource()
        let videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        return CallTracks(videoTrack: videoTrack)
    }

    func makeCallCreator(
        for dataConnected: PeerDataConnectionState.Connected,
        tracks: CallTracks,
        role: CallRole
    ) -> CallCreatorProtocol {
        switch role {
        case .initiator:
            CallInitiator(
                connectionWrapper: dataConnected.connection,
                dataChannelWrapper: dataConnected.dataChannel,
                localTracks: tracks,
                logger: logger
            )
        case .acceptor:
            CallAcceptor(
                connectionWrapper: dataConnected.connection,
                dataChannelWrapper: dataConnected.dataChannel,
                localTracks: tracks,
                logger: logger
            )
        }
    }

    func reportMediaState(
        callCreator: CallCreatorProtocol,
        multiplexedChannel: MultiplexedDataChannel
    ) async {
        do {
            let stateSequence = callCreator.subscribeState()

            for try await state in stateSequence {
                guard !Task.isCancelled else { return }

                switch state {
                case .creating:
                    stateSubject.send(.connecting)
                case let .ready(tracks):
                    let connected = VideoGamePeerEngineState.Connected(
                        multiplexedChannel: multiplexedChannel,
                        remoteVideoTrack: tracks.videoTrack
                    )
                    stateSubject.send(.connected(connected))
                case .closed:
                    stateSubject.send(.disconnected)
                }
            }
        } catch {
            logError("Media state reporting error: \(error)")
            stateSubject.send(.disconnected)
        }
    }

    // MARK: - Reconnection

    func subscribeToReconnection(session: VideoGameSignalingSession) {
        let task = Task { [weak self] in
            do {
                for try await offerId in session.reconnectedSignals {
                    guard !Task.isCancelled else { return }

                    guard let self else { return }

                    let lastOfferId = attemptTracker.getLastOfferId(
                        gameIndex: gameIndex,
                        remoteAccountId: remoteAccountId
                    )

                    guard lastOfferId == offerId else {
                        logDebug("Ignoring reconnected with mismatched offer ID: \(offerId)")
                        continue
                    }

                    logDebug("Reconnection requested for offer ID: \(offerId)")

                    // Cancel any in-flight connection and restart.
                    // resetForReconnection() replaces the signal subject so that
                    // the new DataConnectionCreator doesn't receive stale offers/answers.
                    let connTask = mutex.withLock { self.connectionTask }
                    connTask?.cancel()
                    disposeCurrentConnection()
                    session.resetForReconnection()

                    let newTask = Task { [weak self] in
                        guard let self else { return }
                        await performReconnection(session: session)
                    }
                    mutex.withLock { self.connectionTask = newTask }
                }
            } catch {
                self?.logError("Reconnection subscription error: \(error)")
            }
        }
        mutex.withLock { reconnectionTask = task }
    }

    /// Tears down the current WebRTC connection and its creators.
    func disposeCurrentConnection() {
        let (call, dataConn, connection) = mutex.withLock {
            let snapshot = (callCreator, dataConnectionCreator, connectionWrapper)
            callCreator = nil
            dataConnectionCreator = nil
            connectionWrapper = nil
            return snapshot
        }

        call?.throttle()
        dataConn?.throttle()
        connection?.connection.close()
    }

    func performReconnection(session: VideoGameSignalingSession) async {
        stateSubject.send(.connecting)

        let role: CallRole = isInitiator ? .initiator : .acceptor

        let dataCreator = makeDataConnectionCreator(signaling: session, role: role)
        mutex.withLock { dataConnectionCreator = dataCreator }

        guard let stateSequence = await createConnection(with: dataCreator) else {
            logError("Reconnection data channel creation failed")
            stateSubject.send(.disconnected)
            return
        }

        guard let dataConnected = await waitDataChannelConnected(from: stateSequence) else {
            stateSubject.send(.disconnected)
            return
        }

        guard !Task.isCancelled else { return }

        if let offerId = session.activeOfferId {
            attemptTracker.persistOfferId(
                offerId,
                gameIndex: gameIndex,
                remoteAccountId: remoteAccountId
            )
        }

        dataCreator.throttle()
        mutex.withLock { dataConnectionCreator = nil }

        let localTracks = createVideoOnlyTracks()
        let mediaCreator = makeCallCreator(
            for: dataConnected,
            tracks: localTracks,
            role: role
        )

        mutex.withLock {
            connectionWrapper = dataConnected.connection
            callCreator = mediaCreator
        }

        guard !Task.isCancelled else { return }

        mediaCreator.setup()

        let multiplexedChannel = mediaCreator.multiplexedChannel

        await reportMediaState(
            callCreator: mediaCreator,
            multiplexedChannel: multiplexedChannel
        )
    }
}
