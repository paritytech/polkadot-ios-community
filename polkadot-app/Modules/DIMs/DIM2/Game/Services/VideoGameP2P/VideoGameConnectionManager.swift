import Foundation
import SubstrateSdk
import AsyncExtensions
import WebRTC
import Individuality

/// Reports connection state changes from the 1:N peer channel manager.
protocol VideoGameConnectionManagerDelegate: AnyObject {
    func connectionManager(
        _ manager: VideoGameConnectionManaging,
        didUpdateConnectionStates states: [AccountId: VideoGamePeerEngineState]
    )
}

protocol VideoGameConnectionManaging: AnyObject {
    var delegate: VideoGameConnectionManagerDelegate? { get set }

    /// The local video track to send over the peer connection.
    var localVideoTrack: RTCVideoTrack? { get set }

    /// Reconciles the set of active remote players with the current peer channels.
    /// Creates new channels for added players and disposes channels for removed players.
    func setConnectedPlayers(_ remotePlayers: Set<AccountId>, gameIndex: GamePallet.GameIndex)

    /// Disposes all peer channels and clears state.
    func disconnectAll()

    /// Clears persisted offer IDs for all active peer channels.
    func clearPersistedOfferIds()

    func peerEngineState(for accountId: AccountId) -> VideoGamePeerEngineState?
}

final class VideoGameConnectionManager {
    weak var delegate: VideoGameConnectionManagerDelegate?
    var localVideoTrack: RTCVideoTrack?

    private let localAccountId: AccountId
    private let sessionFactory: VideoGameSessionMaking
    private let attemptTracker: ConnectionAttemptTracking
    private let callbackQueue: DispatchQueue
    private let turnService: TURNCredentialsProviding
    private let logger: LoggerProtocol

    private let mutex = NSLock()
    private var peerChannels: [AccountId: VideoGamePeerEngine] = [:]
    private var peerStates: [AccountId: VideoGamePeerEngineState] = [:]
    private var observationTasks: [AccountId: Task<Void, Never>] = [:]

    init(
        localAccountId: AccountId,
        sessionFactory: VideoGameSessionMaking,
        attemptTracker: ConnectionAttemptTracking,
        callbackQueue: DispatchQueue,
        turnService: TURNCredentialsProviding,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localAccountId = localAccountId
        self.sessionFactory = sessionFactory
        self.attemptTracker = attemptTracker
        self.callbackQueue = callbackQueue
        self.turnService = turnService
        self.logger = logger

        logger.debug("Initialized with local account: \(localAccountId.toHex())")
    }

    deinit {
        logger.debug("Deinit")
    }
}

// MARK: - VideoGameConnectionManaging

extension VideoGameConnectionManager: VideoGameConnectionManaging {
    func setConnectedPlayers(_ remotePlayers: Set<AccountId>, gameIndex: GamePallet.GameIndex) {
        let currentPeers = mutex.withLock { Set(peerChannels.keys) }
        let actualRemotePlayers = remotePlayers.filter { $0 != localAccountId }

        let toAdd = actualRemotePlayers.subtracting(currentPeers)
        let toRemove = currentPeers.subtracting(actualRemotePlayers)

        // Clear offer IDs and dispose removed channels (offer is no longer valid)
        for accountId in toRemove {
            removeChannel(for: accountId, clearsOfferId: true)
        }

        // Create new channels
        for accountId in toAdd {
            addChannel(for: accountId, gameIndex: gameIndex)
        }

        if !toAdd.isEmpty || !toRemove.isEmpty {
            let total = mutex.withLock { peerChannels.count }
            logger.debug(
                "Players updated: added=\(toAdd.count), removed=\(toRemove.count), total=\(total)"
            )
        }
    }

    func disconnectAll() {
        let allAccountIds = mutex.withLock { Array(peerChannels.keys) }

        for accountId in allAccountIds {
            removeChannel(for: accountId)
        }
    }

    func clearPersistedOfferIds() {
        let channels = mutex.withLock { Array(peerChannels.values) }

        for channel in channels {
            channel.clearPersistedOfferId()
        }
    }

    func peerEngineState(for accountId: SubstrateSdk.AccountId) -> VideoGamePeerEngineState? {
        mutex.withLock {
            peerStates[accountId]
        }
    }
}

// MARK: - Private

private extension VideoGameConnectionManager {
    func addChannel(for remoteAccountId: AccountId, gameIndex: GamePallet.GameIndex) {
        let channel = VideoGamePeerEngine(
            localAccountId: localAccountId,
            remoteAccountId: remoteAccountId,
            gameIndex: gameIndex,
            localVideoTrack: localVideoTrack,
            sessionFactory: sessionFactory,
            attemptTracker: attemptTracker,
            configFactory: WebRTCConfigFactory(turnService: turnService),
            logger: logger
        )

        // Start observing channel state
        let task = Task { [weak self, weak channel] in
            guard let channel else { return }

            do {
                for try await state in channel.stateStream() {
                    guard !Task.isCancelled else { return }

                    self?.handleStateUpdate(state, for: remoteAccountId)
                }
            } catch {
                self?.logger.error("State observation error for peer: \(error)")
            }
        }

        mutex.withLock {
            peerChannels[remoteAccountId] = channel
            peerStates[remoteAccountId] = .connecting
            observationTasks[remoteAccountId] = task
        }

        channel.start()
    }

    func removeChannel(for remoteAccountId: AccountId, clearsOfferId: Bool = false) {
        let channel: VideoGamePeerEngine? = mutex.withLock {
            observationTasks[remoteAccountId]?.cancel()
            observationTasks.removeValue(forKey: remoteAccountId)

            let channel = peerChannels.removeValue(forKey: remoteAccountId)
            peerStates.removeValue(forKey: remoteAccountId)
            return channel
        }

        if clearsOfferId {
            channel?.clearPersistedOfferId()
        }

        channel?.dispose()
    }

    func handleStateUpdate(_ state: VideoGamePeerEngineState, for remoteAccountId: AccountId) {
        let states = mutex.withLock {
            peerStates[remoteAccountId] = state
            return peerStates
        }

        callbackQueue.async { [weak self] in
            guard let self else { return }
            delegate?.connectionManager(self, didUpdateConnectionStates: states)
        }
    }
}
