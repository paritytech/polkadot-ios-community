import Foundation
import WebRTC
import SubstrateSdk
import AsyncExtensions

enum DeviceSyncDataChannelState {
    case connected
    case disconnected
}

enum DeviceSyncDataChannelError: Error {
    case connectionFailed
    case notConnected
    case encodingFailed(Error)
    case decodingFailed(Error)
    case sendFailed
}

protocol DeviceSyncDataChanneling: Actor {
    nonisolated var updates: AnyAsyncSequence<Chat.DeviceSyncUpdate> { get }
    nonisolated var acks: AnyAsyncSequence<Chat.DeviceSyncUpdateAck> { get }
    nonisolated var states: AnyAsyncSequence<DeviceSyncDataChannelState> { get }

    func connect() async throws
    func sendUpdate(_ update: Chat.DeviceSyncUpdate) async throws
    func sendAck(_ ack: Chat.DeviceSyncUpdateAck) async throws
    func close() async
}

actor DeviceSyncDataChannel {
    private static let purpose = "sync"
    private static let useCaseId = "device-sync"

    private let signaler: DeviceSyncPeerConnectionSignaler
    private let role: CallRole
    private let logger: LoggerProtocol

    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let configFactory: WebRTCConfigMaking

    private var multiplexedChannel: MultiplexedDataChannel?
    private var dataConnectionCreator: DataConnectionCreating?

    private nonisolated let updateSubject = AsyncPassthroughSubject<Chat.DeviceSyncUpdate>()
    private nonisolated let ackSubject = AsyncPassthroughSubject<Chat.DeviceSyncUpdateAck>()
    private nonisolated let stateSubject = AsyncPassthroughSubject<DeviceSyncDataChannelState>()

    private var connectTask: Task<PeerDataConnectionState.Connected?, Never>?
    private var receiveTask: Task<Void, Never>?
    private var connectionMonitorTask: Task<Void, Never>?

    init(
        signaler: DeviceSyncPeerConnectionSignaler,
        role: CallRole,
        configFactory: WebRTCConfigMaking,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.signaler = signaler
        self.role = role
        self.configFactory = configFactory
        self.logger = logger

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    deinit {
        logger.debug("Deinit")
    }
}

// MARK: - Public API

extension DeviceSyncDataChannel: DeviceSyncDataChanneling {
    nonisolated var updates: AnyAsyncSequence<Chat.DeviceSyncUpdate> {
        updateSubject.eraseToAnyAsyncSequence()
    }

    nonisolated var acks: AnyAsyncSequence<Chat.DeviceSyncUpdateAck> {
        ackSubject.eraseToAnyAsyncSequence()
    }

    nonisolated var states: AnyAsyncSequence<DeviceSyncDataChannelState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    func connect() async throws {
        guard dataConnectionCreator == nil, multiplexedChannel == nil else {
            logger.debug("Sync data channel connection already started")
            return
        }

        let creator = makeDataConnectionCreator()
        dataConnectionCreator = creator

        logger.debug("Creating connection as \(role)...")

        let stateSequence: AnyAsyncSequence<PeerDataConnectionState>
        do {
            stateSequence = try await creator.connect()
        } catch {
            logger.error("Creation failed")
            throw DeviceSyncDataChannelError.connectionFailed
        }

        logger.debug("Waiting for connected state...")

        guard let connectedState = await waitForCancellableConnectedState(from: stateSequence) else {
            logger.error("Connection failed")
            throw DeviceSyncDataChannelError.connectionFailed
        }

        try Task.checkCancellation()

        logger.debug("Connection established")

        creator.throttle()

        let muxChannel = MultiplexedDataChannel(
            dataChannelWrapper: connectedState.dataChannel,
            logger: logger
        )
        muxChannel.start()
        multiplexedChannel = muxChannel

        startReceiving(from: muxChannel)
        stateSubject.send(.connected)
        startConnectionMonitoring(connectedState)
    }

    func sendUpdate(_ update: Chat.DeviceSyncUpdate) throws {
        let syncMessage = Chat.DeviceSyncMessage.update(update)
        try sendSyncMessage(syncMessage)
    }

    func sendAck(_ ack: Chat.DeviceSyncUpdateAck) throws {
        let syncMessage = Chat.DeviceSyncMessage.ack(ack)
        try sendSyncMessage(syncMessage)
    }

    func close() {
        cancelConnectTask()
        receiveTask?.cancel()
        receiveTask = nil
        connectionMonitorTask?.cancel()
        connectionMonitorTask = nil

        dataConnectionCreator?.throttle()
        dataConnectionCreator = nil

        multiplexedChannel = nil
    }
}

// MARK: - Connection

extension DeviceSyncDataChannel {
    private func makeDataConnectionCreator() -> DataConnectionCreating {
        switch role {
        case .initiator:
            DataConnectionInitiator(
                signaling: signaler,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                purpose: Self.purpose,
                logger: logger
            )
        case .acceptor:
            DataConnectionAcceptor(
                signaling: signaler,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                logger: logger
            )
        }
    }

    private func waitForCancellableConnectedState(
        from stateSequence: AnyAsyncSequence<PeerDataConnectionState>
    ) async -> PeerDataConnectionState.Connected? {
        let task = Task { [weak self] in
            guard let self else { return nil as PeerDataConnectionState.Connected? }
            return await waitForConnected(from: stateSequence)
        }

        connectTask = task
        let connectedState = await withTaskCancellationHandler {
            await task.value
        } onCancel: { [weak self] in
            Task { await self?.cancelConnectTask() }
        }
        connectTask = nil

        return connectedState
    }

    private func waitForConnected(
        from sequence: AnyAsyncSequence<PeerDataConnectionState>
    ) async -> PeerDataConnectionState.Connected? {
        do {
            for try await state in sequence {
                logger.debug("State: \(state)")
                switch state {
                case let .connected(model):
                    return model
                case .disconnected:
                    return nil
                case .waiting,
                     .connecting:
                    continue
                }
            }
            return nil
        } catch {
            logger.error("Connection state error: \(error)")
            return nil
        }
    }

    private func cancelConnectTask() {
        connectTask?.cancel()
        connectTask = nil
    }
}

// MARK: - Sending / Receiving

extension DeviceSyncDataChannel {
    private func startConnectionMonitoring(_ connectedState: PeerDataConnectionState.Connected) {
        connectionMonitorTask?.cancel()

        connectionMonitorTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self?.observeDataChannelState(connectedState.dataChannel)
                }
                group.addTask {
                    await self?.observeIceConnectionState(connectedState.connection)
                }
            }
        }
    }

    private func observeDataChannelState(_ wrapper: AsyncDataChannelWrapper) async {
        do {
            for try await state in wrapper.state.eraseToAnyAsyncSequence() {
                guard !Task.isCancelled else { return }

                if state == .closed {
                    logger.warning("Sync data channel closed")
                    stateSubject.send(.disconnected)
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Sync data channel state observation failed: \(error)")
            stateSubject.send(.disconnected)
        }
    }

    private func observeIceConnectionState(_ wrapper: AsyncPeerConnectionWrapper) async {
        do {
            for try await state in wrapper.iceConnectionState.eraseToAnyAsyncSequence() {
                guard !Task.isCancelled else { return }

                switch state {
                case .failed,
                     .closed:
                    logger.warning("Sync ICE connection lost: \(String(describing: state))")
                    stateSubject.send(.disconnected)
                    return
                case .disconnected:
                    logger.warning("ICE disconnect, but will try another one")
                case .new,
                     .checking,
                     .connected,
                     .completed,
                     .count,
                     nil:
                    continue
                @unknown default:
                    continue
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Sync ICE state observation failed: \(error)")
            stateSubject.send(.disconnected)
        }
    }

    private func startReceiving(from muxChannel: MultiplexedDataChannel) {
        let syncStream = muxChannel.subscribe(useCaseId: Self.useCaseId)

        receiveTask = Task { [weak self] in
            do {
                for try await data in syncStream {
                    guard !Task.isCancelled else { return }
                    await self?.handleReceivedData(data)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await self?.handleReceiveError(error)
            }
        }
    }

    private func handleReceiveError(_ error: Error) {
        logger.error("Sync data stream failed: \(error)")
    }

    private func sendSyncMessage(_ syncMessage: Chat.DeviceSyncMessage) throws {
        guard let muxChannel = multiplexedChannel else {
            logger.warning("Cannot send sync data: channel not connected")
            throw DeviceSyncDataChannelError.notConnected
        }

        let syncData = try syncMessage.scaleEncoded()
        logger.debug("Sending \(syncData.count) bytes")
        try muxChannel.send(data: syncData, useCaseId: Self.useCaseId)
    }

    private func handleReceivedData(_ data: Data) {
        logger.debug("Received \(data.count) bytes")

        do {
            let syncDecoder = try ScaleDecoder(data: data)
            let syncMessage = try Chat.DeviceSyncMessage(scaleDecoder: syncDecoder)

            switch syncMessage {
            case let .update(update):
                updateSubject.send(update)
            case let .ack(ack):
                ackSubject.send(ack)
            }
        } catch {
            logger.error("Sync message decoding failed: \(error)")
        }
    }
}
