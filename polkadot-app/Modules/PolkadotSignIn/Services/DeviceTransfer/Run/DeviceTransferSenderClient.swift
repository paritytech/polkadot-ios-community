import Foundation
import FoundationExt
import StructuredConcurrency
import IssueMonitoring

final class DeviceTransferSenderClient: DeviceTransferClientProtocol {
    private let flow: any DevicePeerConnectionFlowing
    private let sequencer: DeviceTransferSenderSequencing
    private let deviceKeyManager: DeviceEncryptionKeyManaging
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let dataFailureDiagnostic: IssueDiagnostic
    private let settings: DeviceTransferSenderSettings

    init(
        flow: any DevicePeerConnectionFlowing,
        sequencer: DeviceTransferSenderSequencing,
        dependencies: DeviceTransferSenderDependencies,
        settings: DeviceTransferSenderSettings = DeviceTransferSenderSettings()
    ) {
        self.flow = flow
        self.sequencer = sequencer
        deviceKeyManager = dependencies.deviceKeyManager
        updateIdProvider = dependencies.updateIdProvider
        dataFailureDiagnostic = dependencies.dataFailureDiagnostic
        self.settings = settings
    }

    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        let channel = await DeviceTransferSenderChannel(
            flow: flow,
            updateIdProvider: updateIdProvider,
            settings: settings
        )

        do {
            try await flow.abortOnLocalFailure(reportingTo: dataFailureDiagnostic, as: "sender") {
                try await transfer(over: channel, onEvent: onEvent)
            }
            await channel.close()
        } catch {
            await channel.close()
            throw error
        }
    }
}

struct DeviceTransferSenderDependencies {
    let deviceKeyManager: DeviceEncryptionKeyManaging
    let updateIdProvider: DeviceSyncUpdateIdProviding
    var dataFailureDiagnostic: IssueDiagnostic = NoopIssueDiagnostic()
}

private extension DeviceTransferSenderClient {
    func transfer(over channel: DeviceTransferSenderChannel, onEvent: DeviceTransferRunEventHandler) async throws {
        let flow = flow
        try await withTimeout(settings.connectTimeout) { try await flow.start() }

        let resumePoint = try await channel.waitForResume()
        var sent = 0
        var total = 0

        var steps = sequencer.entitySequence(from: resumePoint).makeAsyncIterator()

        while let step = try await DeviceTransferLocalFailureHandler.withLocalFailure({ try await steps.next() }) {
            try await send(step, over: channel)

            switch step {
            case let .started(totalChanges):
                total = Int(totalChanges)
            case let .entities(entities, _):
                sent += entities.reduce(0) { $0 + $1.itemCount }
            case .roundClosed:
                continue
            }

            onEvent(.progress(.syncing(applied: sent, total: total)))
        }

        try await flow.sendTransferControl(.senderCompleted)
        try await channel.waitForReceiverCompleted()
    }

    func send(_ step: DeviceTransferSenderStep, over channel: DeviceTransferSenderChannel) async throws {
        switch step {
        case let .started(totalChanges):
            let deviceKeyManager = deviceKeyManager
            let deviceKey = try await DeviceTransferLocalFailureHandler.withLocalFailure {
                try deviceKeyManager.getOrCreatePrivateKey()
            }
            try await flow.sendTransferControl(
                .senderStarted(deviceEncryptionKey: deviceKey.rawRepresentation, totalChanges: totalChanges)
            )
        case let .entities(entities, timePoint):
            try await channel.deliver(entities, timePoint: timePoint)
        case let .roundClosed(timePoint):
            try await channel.deliver([], timePoint: timePoint)
        }
    }
}
