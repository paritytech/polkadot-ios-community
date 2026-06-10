import Foundation
import CryptoKit
import SubstrateSdk
import StatementStore
import MessageExchangeKit
import AsyncExtensions
import Operation_iOS
import FoundationExt

struct DeviceSyncRestartDelayPolicy {
    let maxDelaySeconds: Int = 30

    func delay(forAttempt attempt: Int) -> Duration {
        let exponent = min(max(attempt - 1, 0), 5)
        let seconds = min(1 << exponent, maxDelaySeconds)
        return .seconds(seconds)
    }
}

protocol DeviceSyncServicing {
    func setup(configuration: DeviceSyncServiceConfiguration) async
    func throttle() async
}

struct DeviceSyncServiceConfiguration {
    let connection: StatementStoreConnecting
    let signerManager: StatementStoreSignerManaging
    let encryptionManager: MessageExchangeEncryptionManaging
    let ownSignKeyId: String
    let ownEncryptionKeyId: String
}

actor DeviceSyncService {
    private let ownStatementAccountId: Data
    private let configFactory: WebRTCConfigMaking
    private let remoteContactResolver: RemoteContactResolving
    private let deviceDataProviderFactory: LocalDeviceDataProviderMaking
    private let deviceRepositoryFactory: LocalDeviceRepositoryMaking
    private let contactRepositoryFactory: ChatContactRepositoryMaking
    private let chatRepositoryFactory: ChatRepositoryMaking
    private let messageRepositoryFactory: ChatMessageRepositoryMaking
    private let removedChatRepositoryFactory: RemovedChatRepositoryMaking
    private let messageExchangeModeProvider: MessageExchangeModeProviding
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let restartDelayPolicy: DeviceSyncRestartDelayPolicy
    private let foregroundRecoveryController: DeviceSyncForegroundRecoveryController
    private let logger: LoggerProtocol

    private var syncSessions = [Data: DeviceSyncSession]()
    private var restartTasks = [Data: Task<Void, Never>]()
    private var restartAttempts = [Data: Int]()
    private var deviceSubscriptionTask: Task<Void, Never>?

    private var configuration: DeviceSyncServiceConfiguration?

    init(
        ownStatementAccountId: Data,
        messageExchangeModeProvider: MessageExchangeModeProviding,
        configFactory: WebRTCConfigMaking,
        remoteContactResolver: RemoteContactResolving = RemoteContactOperationFactory(),
        deviceDataProviderFactory: LocalDeviceDataProviderMaking = LocalDeviceDataProviderFactory(),
        deviceRepositoryFactory: LocalDeviceRepositoryMaking = LocalDeviceRepositoryFactory(),
        contactRepositoryFactory: ChatContactRepositoryMaking = ChatContactRepositoryFactory(),
        chatRepositoryFactory: ChatRepositoryMaking = ChatRepositoryFactory(),
        messageRepositoryFactory: ChatMessageRepositoryMaking = ChatMessageRepositoryFactory(),
        removedChatRepositoryFactory: RemovedChatRepositoryMaking = RemovedChatRepositoryFactory(),
        updateIdProvider: DeviceSyncUpdateIdProviding = DeviceSyncUpdateIdProvider(),
        restartDelayPolicy: DeviceSyncRestartDelayPolicy = DeviceSyncRestartDelayPolicy(),
        applicationStateStreamFactory: ApplicationStateStreamFactory = ApplicationStateStreamFactory(),
        foregroundRecoveryController: DeviceSyncForegroundRecoveryController? = nil,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.ownStatementAccountId = ownStatementAccountId
        self.configFactory = configFactory
        self.remoteContactResolver = remoteContactResolver
        self.deviceDataProviderFactory = deviceDataProviderFactory
        self.deviceRepositoryFactory = deviceRepositoryFactory
        self.contactRepositoryFactory = contactRepositoryFactory
        self.chatRepositoryFactory = chatRepositoryFactory
        self.messageRepositoryFactory = messageRepositoryFactory
        self.removedChatRepositoryFactory = removedChatRepositoryFactory
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.updateIdProvider = updateIdProvider
        self.restartDelayPolicy = restartDelayPolicy
        self.logger = logger
        self.foregroundRecoveryController = foregroundRecoveryController ?? DeviceSyncForegroundRecoveryController(
            applicationStateStreamFactory: applicationStateStreamFactory,
            logger: logger
        )
    }

    deinit {
        logger.debug("Deinit")
    }
}

// MARK: - DeviceSyncServicing

extension DeviceSyncService: DeviceSyncServicing {
    func setup(configuration: DeviceSyncServiceConfiguration) async {
        self.configuration = configuration

        startDeviceSubscription()
        await foregroundRecoveryController.start { [weak self] in
            await self?.recoverForegroundSessions()
        }
    }

    func throttle() async {
        deviceSubscriptionTask?.cancel()
        deviceSubscriptionTask = nil
        await foregroundRecoveryController.stop()

        for (_, task) in restartTasks {
            task.cancel()
        }
        restartTasks.removeAll()
        restartAttempts.removeAll()

        for (_, session) in syncSessions {
            await session.close()
        }
        syncSessions.removeAll()

        configuration = nil
    }
}

// MARK: - Device Observation

private extension DeviceSyncService {
    func startDeviceSubscription() {
        deviceSubscriptionTask?.cancel()
        deviceSubscriptionTask = Task { [weak self] in
            await self?.runDeviceSubscription()
        }
    }

    func runDeviceSubscription() async {
        let stream = deviceDataProviderFactory.subscribeDevices()

        do {
            for try await devices in stream {
                guard !Task.isCancelled else { return }
                await handleDevicesUpdate(devices)
            }
        } catch {
            logger.error("Device subscription failed: \(error)")
        }
    }

    func handleDevicesUpdate(_ devices: [Chat.LocalDevice]) async {
        let remoteDevices = devices.filter {
            $0.statementAccountId != ownStatementAccountId && $0.supportsDeviceSyncSession
        }
        let remoteAccountIds = Set(remoteDevices.map(\.statementAccountId))

        // Remove sessions for devices that are no longer present
        let removedIds = Set(syncSessions.keys).subtracting(remoteAccountIds)
        for removedId in removedIds {
            logger.debug("Removing sync session for device \(removedId.toHex())")
            restartTasks[removedId]?.cancel()
            restartTasks.removeValue(forKey: removedId)
            restartAttempts.removeValue(forKey: removedId)
            await syncSessions[removedId]?.close()
            syncSessions.removeValue(forKey: removedId)
        }

        // Start sessions for new devices
        for device in remoteDevices {
            guard syncSessions[device.statementAccountId] == nil else {
                continue
            }
            await startSyncSession(for: device)
        }
    }

    func startSyncSession(for device: Chat.LocalDevice) async {
        guard device.supportsDeviceSyncSession else {
            logger.debug("Skip device sync session for unsupported host: \(device.hostName)")
            return
        }

        guard let configuration else {
            logger.warning("Cannot start sync session: service not configured")
            return
        }

        let transport = makeTransport(for: device, configuration: configuration)
        await transport.open()

        let role = determineSyncRole(peerAccountId: device.statementAccountId)
        let (signaler, dataChannel) = createDataChannel(transport: transport, role: role)

        logger.debug("Starting sync with \(device.statementAccountId.toHex()), role=\(role)")

        let session = makeSyncSession(
            for: device,
            transport: transport,
            signaler: signaler,
            dataChannel: dataChannel,
            reconnectOfferId: device.lastSyncOfferId
        )

        syncSessions[device.statementAccountId] = session
        await session.start()

        if syncSessions[device.statementAccountId] === session {
            restartAttempts[device.statementAccountId] = 0
        }
    }

    func makeTransport(
        for device: Chat.LocalDevice,
        configuration: DeviceSyncServiceConfiguration
    ) -> DeviceSyncMessageTransport {
        DeviceSyncMessageTransport(
            connection: configuration.connection,
            signerManager: configuration.signerManager,
            encryptionManager: configuration.encryptionManager,
            ownSignKeyId: configuration.ownSignKeyId,
            ownEncryptionKeyId: configuration.ownEncryptionKeyId,
            peerStatementAccountId: device.statementAccountId,
            peerEncryptionPublicKey: device.encryptionPublicKey,
            logger: logger
        )
    }

    func makeSyncSession(
        for device: Chat.LocalDevice,
        transport: DeviceSyncMessageTransport,
        signaler: DeviceSyncPeerConnectionSignaler,
        dataChannel: DeviceSyncDataChannel,
        reconnectOfferId: String?
    ) -> DeviceSyncSession {
        DeviceSyncSession(
            peerStatementAccountId: device.statementAccountId,
            initialCheckpoint: device.outgoingUpdateTime,
            transport: transport,
            signaler: signaler,
            dataChannel: dataChannel,
            remoteContactResolver: remoteContactResolver,
            deviceRepositoryFactory: deviceRepositoryFactory,
            contactRepositoryFactory: contactRepositoryFactory,
            chatRepositoryFactory: chatRepositoryFactory,
            messageRepositoryFactory: messageRepositoryFactory,
            contactDataProviderFactory: ChatContactDataProviderFactory(
                repositoryFactory: contactRepositoryFactory,
                logger: logger
            ),
            messageDataProviderFactory: ChatMessageDataProviderFactory(
                repositoryFactory: messageRepositoryFactory,
                logger: logger
            ),
            removedChatRepositoryFactory: removedChatRepositoryFactory,
            messageExchangeModeProvider: messageExchangeModeProvider,
            outgoingUpdateTimeRepositoryFactory: OutgoingUpdateTimeRepositoryFactory(),
            updateIdProvider: updateIdProvider,
            logger: logger,
            pushInitialUpdate: true,
            reconnectOfferId: reconnectOfferId,
            entityApplyOverride: nil,
            failureHandler: { [weak self] session, peerStatementAccountId, failure in
                await self?.handleSessionFailure(
                    session: session,
                    peerStatementAccountId: peerStatementAccountId,
                    failure: failure
                )
            }
        )
    }

    func createDataChannel(
        transport: DeviceSyncMessageTransporting,
        role: CallRole
    ) -> (DeviceSyncPeerConnectionSignaler, DeviceSyncDataChannel) {
        let signaler = DeviceSyncPeerConnectionSignaler(
            transport: transport,
            role: role,
            logger: logger
        )

        let dataChannel = DeviceSyncDataChannel(
            signaler: signaler,
            role: role,
            configFactory: configFactory,
            logger: logger
        )

        return (signaler, dataChannel)
    }

    func determineSyncRole(peerAccountId: Data) -> CallRole {
        // Deterministic role: device with lexicographically smaller account ID initiates
        ownStatementAccountId.lexicographicallyPrecedes(peerAccountId)
            ? .initiator
            : .acceptor
    }
}

// MARK: - Foreground Recovery

private extension DeviceSyncService {
    func recoverForegroundSessions() async {
        guard configuration != nil else { return }

        let peerAccountIds = Set(syncSessions.keys).union(restartTasks.keys)
        guard !peerAccountIds.isEmpty else { return }

        logger.debug("Recovering \(peerAccountIds.count) device sync session(s) on foreground")

        for peerAccountId in peerAccountIds {
            restartTasks[peerAccountId]?.cancel()
            restartTasks.removeValue(forKey: peerAccountId)
            restartAttempts[peerAccountId] = 0

            await syncSessions[peerAccountId]?.close()
            syncSessions.removeValue(forKey: peerAccountId)

            scheduleRestart(for: peerAccountId, delay: nil)
        }
    }
}

// MARK: - Session Recovery

private extension DeviceSyncService {
    func handleSessionFailure(
        session: DeviceSyncSession,
        peerStatementAccountId: Data,
        failure: DeviceSyncSessionFailure
    ) async {
        // Foreground recovery can close and replace a session while that old session is
        // still unwinding from a connection timeout/disconnect. Ignore failures from
        // sessions that are no longer registered as current, otherwise the stale failure
        // can cancel the immediate foreground reconnect and replace it with backoff.
        guard syncSessions[peerStatementAccountId] === session else {
            logger.debug(
                "Ignoring stale device sync session failure for \(peerStatementAccountId.toHex()): \(failure)"
            )
            return
        }

        logger.error(
            "Device sync session failed for \(peerStatementAccountId.toHex()), scheduling recovery: \(failure)"
        )

        await syncSessions[peerStatementAccountId]?.close()
        syncSessions.removeValue(forKey: peerStatementAccountId)

        scheduleRestart(for: peerStatementAccountId)
    }

    func scheduleRestart(for peerStatementAccountId: Data) {
        let attempt = (restartAttempts[peerStatementAccountId] ?? 0) + 1
        restartAttempts[peerStatementAccountId] = attempt

        scheduleRestart(
            for: peerStatementAccountId,
            delay: restartDelayPolicy.delay(forAttempt: attempt)
        )
    }

    func scheduleRestart(
        for peerStatementAccountId: Data,
        delay: Duration?
    ) {
        restartTasks[peerStatementAccountId]?.cancel()

        logger.debug(
            "Scheduling device sync restart for \(peerStatementAccountId.toHex()) in \(String(describing: delay))"
        )

        restartTasks[peerStatementAccountId] = Task { [weak self] in
            if let delay {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }

            await self?.restartSyncSession(for: peerStatementAccountId)
        }
    }

    func restartSyncSession(for peerStatementAccountId: Data) async {
        restartTasks.removeValue(forKey: peerStatementAccountId)

        guard syncSessions[peerStatementAccountId] == nil else {
            return
        }

        do {
            let device = try await deviceRepositoryFactory
                .createRepository(forFilter: nil)
                .fetchOperation(by: { peerStatementAccountId.toHex() }, options: .init())
                .asyncExecute()

            guard let device else {
                logger.debug("Skip device sync restart, device removed: \(peerStatementAccountId.toHex())")
                restartAttempts.removeValue(forKey: peerStatementAccountId)
                return
            }

            guard device.supportsDeviceSyncSession else {
                logger.debug("Skip device sync restart for unsupported host: \(device.hostName)")
                restartAttempts.removeValue(forKey: peerStatementAccountId)
                return
            }

            await startSyncSession(for: device)
        } catch {
            logger.error("Failed to restart device sync session: \(error)")
            scheduleRestart(for: peerStatementAccountId)
        }
    }
}
