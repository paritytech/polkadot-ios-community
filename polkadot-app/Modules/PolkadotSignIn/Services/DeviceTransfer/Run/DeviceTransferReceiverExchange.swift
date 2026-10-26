import Foundation

struct DeviceTransferProgress: Equatable {
    /// What the sender counted for its first round; later rounds can push `applied` past it.
    let total: Int
    let applied: Int
}

struct DeviceTransferReceiverSettings {
    var responseTimeout: Duration = .seconds(60)
    var sleep: DeviceSyncSleep = liveDeviceSyncSleep
}

struct DeviceTransferReceiverDependencies {
    /// Built over the transfer's flow, saving messages at the sender's order.
    let updateApplier: DeviceSyncIncomingUpdateApplier
    let coinageStateApplier: DeviceSyncCoinageStateApplying
    let checkpointStore: DeviceTransferCheckpointStoring
    let deviceKeyManager: DeviceEncryptionKeyManaging
    let logger: LoggerProtocol
}

/// New phone's side of one transfer connection (RFC §7.2). Updates go straight to the database; only claim
/// statuses whose message hasn't arrived yet wait in memory. A round's closing update moves the persisted
/// checkpoint, unless such a claim is still waiting, so a later connection resends it.
struct DeviceTransferReceiverExchange {
    private let flow: any DevicePeerConnectionFlowing
    private let senderInstallationId: Data
    private let dependencies: DeviceTransferReceiverDependencies
    private let settings: DeviceTransferReceiverSettings

    init(
        flow: any DevicePeerConnectionFlowing,
        senderInstallationId: Data,
        dependencies: DeviceTransferReceiverDependencies,
        settings: DeviceTransferReceiverSettings = DeviceTransferReceiverSettings()
    ) {
        self.flow = flow
        self.senderInstallationId = senderInstallationId
        self.dependencies = dependencies
        self.settings = settings
    }

    func run(onProgress: @escaping (DeviceTransferProgress) -> Void) async throws {
        var events = await DeviceTransferEventStream(
            flow: flow,
            timeout: settings.responseTimeout,
            sleep: settings.sleep
        )
        defer { events.close() }

        let checkpoint = dependencies.checkpointStore.checkpoint(for: senderInstallationId)
        try await flow.sendTransferControl(.resume(fromTimePoint: checkpoint))

        var session = DeviceTransferReceiverSession(
            senderInstallationId: senderInstallationId,
            dependencies: dependencies,
            onProgress: onProgress
        )

        while try await !session.handle(events.next()) {}

        try await flow.sendTransferControl(.receiverCompleted)
    }
}

private struct DeviceTransferReceiverSession {
    let senderInstallationId: Data
    let dependencies: DeviceTransferReceiverDependencies
    let onProgress: (DeviceTransferProgress) -> Void

    private var total: Int?
    private var applied = 0
    /// Updates are a separate stream from controls, so one can overtake `senderStarted`.
    private var earlyUpdates: [Chat.DeviceSyncUpdate] = []
    private var waitingClaims: [Chat.DeviceSyncCoinageMessageStatusUpdate] = []

    init(
        senderInstallationId: Data,
        dependencies: DeviceTransferReceiverDependencies,
        onProgress: @escaping (DeviceTransferProgress) -> Void
    ) {
        self.senderInstallationId = senderInstallationId
        self.dependencies = dependencies
        self.onProgress = onProgress
    }

    /// Returns `true` once the sender has completed.
    mutating func handle(_ event: DeviceTransferEvent) async throws -> Bool {
        switch event {
        case let .control(.senderStarted(deviceEncryptionKey, totalChanges)):
            try dependencies.deviceKeyManager.importPrivateKey(deviceEncryptionKey)
            total = Int(totalChanges)
            applied = 0
            reportProgress()
            try await applyEarlyUpdates()
        case .control(.senderCompleted):
            dropWaitingClaims()
            return true
        case let .update(update):
            if total == nil {
                earlyUpdates.append(update)
            } else {
                try await apply(update)
            }
        case .control,
             .ack:
            break
        }

        return false
    }
}

private extension DeviceTransferReceiverSession {
    mutating func applyEarlyUpdates() async throws {
        let updates = earlyUpdates
        earlyUpdates = []

        for update in updates {
            try await apply(update)
        }
    }

    mutating func apply(_ update: Chat.DeviceSyncUpdate) async throws {
        guard !update.entities.isEmpty else {
            try await closeRound(at: update)
            return
        }

        waitingClaims += try await dependencies.updateApplier.apply(update)
        applied += update.entities.reduce(0) { $0 + $1.itemCount }
        reportProgress()
    }

    /// A round's messages all precede its closing update, so this is when a waiting claim can find its message.
    mutating func closeRound(at update: Chat.DeviceSyncUpdate) async throws {
        if !waitingClaims.isEmpty {
            waitingClaims = try await dependencies.coinageStateApplier.applyClaimStatuses(waitingClaims)
        }

        try await dependencies.updateApplier.apply(update)

        guard waitingClaims.isEmpty else {
            dependencies.logger.warning("Device transfer checkpoint held back by \(waitingClaims.count) claim(s)")
            return
        }

        dependencies.checkpointStore.save(update.timePoint, senderInstallationId: senderInstallationId)
    }

    mutating func dropWaitingClaims() {
        guard !waitingClaims.isEmpty else { return }

        dependencies.logger.warning("Device transfer dropped \(waitingClaims.count) claim(s) without a message")
        waitingClaims = []
    }

    func reportProgress() {
        guard let total else { return }
        onProgress(DeviceTransferProgress(total: total, applied: applied))
    }
}
