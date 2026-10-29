import Foundation
import StructuredConcurrency

enum DeviceTransferProgress: Equatable {
    /// `total` counts only the first round, so `applied` can pass it.
    case syncing(applied: Int, total: Int)
    case files(DeviceTransferFileProgress)
}

struct DeviceTransferReceiverSettings {
    var connectTimeout: Duration = .seconds(45)
    var responseTimeout: Duration = .seconds(60)
    var clock: any Clock<Duration> = ContinuousClock()
}

struct DeviceTransferReceiverDependencies {
    let updateApplier: DeviceSyncIncomingUpdateApplier
    let coinageStateApplier: DeviceSyncCoinageStateApplying
    let checkpointStore: DeviceTransferCheckpointStoring
    let deviceKeyManager: DeviceEncryptionKeyManaging
    let filePuller: DeviceTransferFilePulling
    let logger: LoggerProtocol
}

final class DeviceTransferReceiverClient: DeviceTransferClientProtocol {
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

    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        let events = await DeviceTransferEventStream.open(
            flow: flow,
            timeout: settings.responseTimeout,
            clock: settings.clock
        )

        do {
            try await transfer(with: events, onEvent: onEvent)
            await events.close()
        } catch {
            await events.close()
            throw error
        }
    }
}

private extension DeviceTransferReceiverClient {
    func transfer(
        with events: DeviceTransferEventStream,
        onEvent: @escaping DeviceTransferRunEventHandler
    ) async throws {
        let flow = flow
        try await withTimeout(settings.connectTimeout) { try await flow.start() }

        let checkpoint = dependencies.checkpointStore.checkpoint(for: senderInstallationId)
        try await flow.sendTransferControl(.resume(fromTimePoint: checkpoint))

        var session = DeviceTransferReceiverSession(
            senderInstallationId: senderInstallationId,
            dependencies: dependencies,
            onProgress: { onEvent(.progress($0)) }
        )

        while try await !session.handle(events.next()) {}

        try await dependencies.filePuller.pullMissingFiles { onEvent(.progress(.files($0))) }
        try await flow.sendTransferControl(.receiverCompleted)
    }
}

private struct DeviceTransferReceiverSession {
    let senderInstallationId: Data
    let dependencies: DeviceTransferReceiverDependencies
    let onProgress: @Sendable (DeviceTransferProgress) -> Void

    private var total: Int?
    private var applied = 0
    /// Updates and controls are separate streams, so an update can overtake `senderStarted`.
    private var earlyUpdates: [Chat.DeviceSyncUpdate] = []
    private var waitingClaims: [Chat.DeviceSyncCoinageMessageStatusUpdate] = []

    init(
        senderInstallationId: Data,
        dependencies: DeviceTransferReceiverDependencies,
        onProgress: @escaping @Sendable (DeviceTransferProgress) -> Void
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

    /// All of a round's messages precede its closing update, so waiting claims are retried here.
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
        onProgress(.syncing(applied: applied, total: total))
    }
}
