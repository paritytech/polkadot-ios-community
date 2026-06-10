import Foundation
import WebRTC
import AsyncExtensions

enum CallEngineError: Error {
    case peerConnectionClosed
    case endOfStream
}

protocol CallEngineProtocol: AnyObject {
    func observeState() -> AnyAsyncSequence<CallEngineState>
    func connect()
    func endCall(notifiesRemote: Bool) async -> PeerConnectionSignalStateObserving?

    func attach(localRenderer: RTCVideoRenderer)
    func attach(remoteRenderer: RTCVideoRenderer)

    var isMuted: Bool { get async }
    func setMuted(_ isMuted: Bool) async -> Bool
}

private actor CallEngineActor {
    var videoCapturer: RTCVideoCapturer?

    var localTracks: CallTracks?
    var localRenderer: RTCVideoRenderer?

    var remoteTracks: CallTracks?
    var remoteRenderer: RTCVideoRenderer?

    var callCreator: CallCreatorProtocol?
    var connectionWrapper: AsyncPeerConnectionWrapper?

    var isMuted: Bool = false
    var hasEnded: Bool = false

    func markEndedIfFirst() -> Bool {
        guard !hasEnded else { return false }
        hasEnded = true
        return true
    }

    func setLocalTracks(_ tracks: CallTracks) {
        localTracks = tracks

        if let audioTrack = localTracks?.audioTrack {
            audioTrack.isEnabled = !isMuted
        }
    }

    func getLocalTracks() -> CallTracks? {
        localTracks
    }

    func setVideoCapturer(_ capturer: RTCVideoCapturer) {
        videoCapturer = capturer
    }

    func setLocalRenderer(_ renderer: RTCVideoRenderer) {
        localRenderer = renderer
    }

    func setRemoteTracks(_ tracks: CallTracks?) {
        remoteTracks = tracks
    }

    func setRemoteRenderer(_ renderer: RTCVideoRenderer) {
        remoteRenderer = renderer
    }

    func setCallCreator(_ callCreator: CallCreatorProtocol) {
        self.callCreator = callCreator
    }

    func setConnectionWrapper(_ connectionWrapper: AsyncPeerConnectionWrapper) {
        self.connectionWrapper = connectionWrapper
    }

    func clearVideoCapture() {
        if let cameraCapturer = videoCapturer as? RTCCameraVideoCapturer {
            cameraCapturer.stopCapture()
        }

        videoCapturer = nil
    }

    func clearTracks() {
        localTracks?.audioTrack?.isEnabled = false
        localTracks?.videoTrack?.isEnabled = false

        localTracks = nil
        localRenderer = nil

        remoteTracks?.audioTrack?.isEnabled = false
        remoteTracks?.videoTrack?.isEnabled = false

        remoteTracks = nil
        remoteRenderer = nil

        videoCapturer = nil
    }

    func clearCallCreator() {
        callCreator?.throttle()
        callCreator = nil
    }

    func toggleMute() -> Bool {
        setMuted(!isMuted)
    }

    func setMuted(_ isMuted: Bool) -> Bool {
        self.isMuted = isMuted

        guard let audioTrack = localTracks?.audioTrack else {
            return isMuted
        }

        audioTrack.isEnabled = !isMuted
        return isMuted
    }

    func getMuteState() -> Bool {
        isMuted
    }
}

final class CallEngine {
    let signaling: PeerConnectionSignaling
    let role: CallRole
    let logger: LoggerProtocol
    let peerConnectionFactory: RTCPeerConnectionFactory
    let configFactory: WebRTCConfigMaking
    let purpose: String

    private var callType: ChatCallType

    private let stateSubject: AsyncCurrentValueSubject<CallEngineState>
    private let stateModel = CallEngineActor()
    private let videoCaptureStrategy: VideoCaptureStrategyProtocol

    private var connectionTask: Task<Void, Never>?
    private var remoteCloseTask: Task<Void, Never>?
    private var offerDeliveryTask: Task<Void, Never>?
    private var iceFailureTask: Task<Void, Never>?

    var supportsVideo: Bool {
        callType == .video
    }

    var supportsAudio: Bool {
        #if targetEnvironment(simulator)
            // simulator doesn't support mic so we disable audio
            false
        #else
            true
        #endif
    }

    init(
        signaling: PeerConnectionSignaling,
        role: CallRole,
        initialCallType: ChatCallType,
        purpose: String,
        configFactory: WebRTCConfigMaking,
        logger: LoggerProtocol
    ) {
        self.signaling = signaling
        self.role = role
        callType = initialCallType
        self.purpose = purpose
        self.configFactory = configFactory
        self.logger = logger

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        videoCaptureStrategy = VideoCaptureStrategy(preferences: .defaultPreferences)

        switch role {
        case .initiator:
            stateSubject = .init(.contacting)
        case .acceptor:
            stateSubject = .init(.waiting)
        }

        observeRemoteClose()
    }

    deinit {
        logger.debug("Deinit")
    }
}

private extension CallEngine {
    func createTracks() -> CallTracks {
        let audioTrack = createAudioTrackIfNeeded()
        let videoTrack = createVideoTrackIfNeeded()

        return CallTracks(audioTrack: audioTrack, videoTrack: videoTrack)
    }

    func createAudioTrackIfNeeded() -> RTCAudioTrack? {
        guard supportsAudio else {
            return nil
        }

        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory.audioSource(with: audioConstraints)
        return peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")
    }

    func createVideoTrackIfNeeded() -> RTCVideoTrack? {
        guard supportsVideo else {
            return nil
        }

        let videoSource = peerConnectionFactory.videoSource()
        return peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
    }

    func makeDataConnectionCreator() -> DataConnectionCreating {
        switch role {
        case .initiator:
            DataConnectionInitiator(
                signaling: signaling,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                purpose: purpose,
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

    func makeCallCreator(
        for dataConnected: PeerDataConnectionState.Connected,
        tracks: CallTracks
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

    func waitDataChannelConnected(
        from sequence: AnyAsyncSequence<PeerDataConnectionState>
    ) async -> PeerDataConnectionState.Connected? {
        do {
            for try await state in sequence {
                switch state {
                case .waiting:
                    stateSubject.send(.contacting)
                case .connecting:
                    stateSubject.send(.connecting)
                case let .connected(model):
                    return model
                case .disconnected:
                    stateSubject.send(.disconnected)
                    return nil
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    func startStateReporting(with callCreator: CallCreatorProtocol) async {
        do {
            let sequence = callCreator.subscribeState()

            for try await state in sequence {
                guard !Task.isCancelled else {
                    return
                }

                switch state {
                case .creating:
                    logger.debug("Call: creating")

                    stateSubject.send(.connecting)
                case let .ready(model):
                    let hasAudio = model.audioTrack != nil
                    let hasVideo = model.videoTrack != nil

                    logger.debug("Call ready: audio=\(hasAudio), video=\(hasVideo)")

                    await stateModel.setRemoteTracks(model)

                    stateSubject.send(.connected)
                case .closed:
                    logger.debug("Call: closed")
                    stateSubject.send(.disconnected)
                }
            }
        } catch {
            logger.error("State reporting error: \(error)")
        }
    }

    func performConnection() async {
        let dataChannelCreator = makeDataConnectionCreator()

        observeOfferDelivery(from: dataChannelCreator)

        guard let connectionStateSequence = try? await dataChannelCreator.connect() else {
            logger.error("Data channel creation failed")
            return
        }

        logger.debug("Establishing data channel...")

        guard let dataChannelConnected = await waitDataChannelConnected(from: connectionStateSequence) else {
            return
        }

        guard !Task.isCancelled else {
            return
        }

        logger.debug("Data channel established")

        dataChannelCreator.throttle()

        let localTracks = createTracks()

        await stateModel.setLocalTracks(localTracks)
        await stateModel.setConnectionWrapper(dataChannelConnected.connection)

        observeIceFailure(on: dataChannelConnected.connection)

        let callCreator = makeCallCreator(for: dataChannelConnected, tracks: localTracks)

        logger.debug("Upgrading to call")

        callCreator.setup()

        await startStateReporting(with: callCreator)

        logger.debug("Completed connection")

        RTCAudioSessionConfiguration.webRTC()
    }

    private func startVideoCapture(from track: RTCVideoTrack) async throws {
        #if targetEnvironment(simulator)
            try await startFileCapturer(for: track)
        #else
            try await startCameraVideoCapture(for: track)
        #endif
    }

    private func startFileCapturer(for track: RTCVideoTrack) async throws {
        let capturer = RTCFileVideoCapturer(delegate: track.source)
        await stateModel.setVideoCapturer(capturer)
        capturer.startCapturing(fromFileNamed: "test.mp4")
    }

    private func startCameraVideoCapture(for track: RTCVideoTrack) async throws {
        let capturer = RTCCameraVideoCapturer(delegate: track.source)
        await stateModel.setVideoCapturer(capturer)

        guard let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }) else {
            logger.error("Front camera not found")
            return
        }

        guard let params = videoCaptureStrategy.deriveParams(for: frontCamera) else {
            logger.error("Can't derive camera params")
            return
        }

        try await capturer.startCapture(
            with: frontCamera,
            format: params.format,
            fps: params.fps
        )

        let dimensions = CMVideoFormatDescriptionGetDimensions(params.format.formatDescription)
        logger.debug("Video capture started: resolution: \(dimensions.width)x\(dimensions.height), fps: \(params.fps)")
    }

    func clearConnectionTask() {
        connectionTask?.cancel()
        connectionTask = nil
    }

    func clearRemoteCloseTask() {
        remoteCloseTask?.cancel()
        remoteCloseTask = nil
    }

    func clearOfferDeliveryTask() {
        offerDeliveryTask?.cancel()
        offerDeliveryTask = nil
    }

    func clearIceFailureTask() {
        iceFailureTask?.cancel()
        iceFailureTask = nil
    }

    func observeOfferDelivery(from creator: DataConnectionCreating) {
        guard role == .initiator else {
            return
        }

        offerDeliveryTask = Task { [weak self, creator] in
            do {
                for try await (signal, observer) in creator.sentSignals {
                    guard case .offer = signal else { continue }
                    try await observer.wait(for: .delivered)
                    guard let self, !Task.isCancelled else { return }
                    if stateSubject.value == .contacting {
                        stateSubject.send(.waiting)
                    }
                    return
                }
            } catch {
                self?.logger.error("Offer delivery observation failed: \(error)")
            }
        }
    }

    func observeIceFailure(on connection: AsyncPeerConnectionWrapper) {
        iceFailureTask = Task { [weak self, connection, logger] in
            let sequence = connection.iceConnectionState.eraseToAnyAsyncSequence()
            do {
                for try await state in sequence where state == .failed {
                    logger.debug("ICE connection failed")
                    self?.stateSubject.send(.failed)
                    return
                }
            } catch {
                logger.error("ICE failure observation failed: \(error)")
            }
        }
    }

    func observeRemoteClose() {
        remoteCloseTask = Task { [weak self, signaling, logger] in
            do {
                for try await signal in signaling.signals {
                    guard !Task.isCancelled else { return }

                    if case .closed = signal {
                        logger.debug("Remote closed signal received; disconnecting")
                        self?.stateSubject.send(.disconnected)
                        return
                    }
                }
            } catch {
                logger.error("Remote close observation failed: \(error)")
            }
        }
    }
}

extension CallEngine: CallEngineProtocol {
    func observeState() -> AnyAsyncSequence<CallEngineState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    func connect() {
        connectionTask = Task { [weak self] in
            await self?.performConnection()
        }
    }

    func endCall(notifiesRemote: Bool) async -> PeerConnectionSignalStateObserving? {
        guard await stateModel.markEndedIfFirst() else {
            logger.debug("endCall ignored — already ended")
            return nil
        }
        logger.debug("Ending call")

        clearConnectionTask()
        clearRemoteCloseTask()
        clearOfferDeliveryTask()
        clearIceFailureTask()

        var observer: PeerConnectionSignalStateObserving?

        if notifiesRemote {
            do {
                observer = try await signaling.send(.closed)
            } catch {
                logger.error("Failed to send close signal: \(error)")
            }
        }

        await stateModel.clearVideoCapture()
        await stateModel.clearTracks()
        await stateModel.clearCallCreator()

        await stateModel.connectionWrapper?.connection.close()

        logger.debug("Call ended")

        return observer
    }

    func attach(localRenderer: RTCVideoRenderer) {
        Task { @MainActor [weak self, stateModel] in
            guard let self else { return }

            let localTracks = await stateModel.localTracks
            let currentRenderer = await stateModel.localRenderer

            guard
                let videoTrack = localTracks?.videoTrack,
                currentRenderer !== localRenderer else {
                return
            }

            await stateModel.setLocalRenderer(localRenderer)
            let maybeCapturer = await stateModel.videoCapturer

            if let currentRenderer {
                videoTrack.remove(currentRenderer)
            }

            videoTrack.add(localRenderer)

            guard maybeCapturer == nil else {
                return
            }

            do {
                try await startVideoCapture(from: videoTrack)
            } catch {
                logger.error("Failed to start video capture: \(error)")
                // Video capture failure doesn't break the call, but should be logged
            }
        }
    }

    func attach(remoteRenderer: RTCVideoRenderer) {
        Task { @MainActor [stateModel] in
            let remoteTracks = await stateModel.remoteTracks
            let currentRenderer = await stateModel.remoteRenderer

            guard
                let videoTrack = remoteTracks?.videoTrack,
                currentRenderer !== remoteRenderer else {
                return
            }

            await stateModel.setRemoteRenderer(remoteRenderer)

            if let currentRenderer {
                videoTrack.remove(currentRenderer)
            }

            videoTrack.add(remoteRenderer)
        }
    }

    var isMuted: Bool {
        get async { await stateModel.isMuted }
    }

    func setMuted(_ isMuted: Bool) async -> Bool {
        let result = await stateModel.setMuted(isMuted)
        logger.debug("Audio muted: \(result)")
        return result
    }
}
