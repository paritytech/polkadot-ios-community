import Foundation
import FoundationExt
import StructuredConcurrency

final class DeviceTransferSenderClient: DeviceTransferClientProtocol {
    private let flow: any DevicePeerConnectionFlowing
    private let sequencer: DeviceTransferSenderSequencing
    private let deviceKeyManager: DeviceEncryptionKeyManaging
    private let updateIdProvider: DeviceSyncUpdateIdProviding
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
        self.settings = settings
    }

    func run(onEvent _: @escaping DeviceTransferRunEventHandler) async throws {
        let channel = await DeviceTransferSenderChannel(
            flow: flow,
            updateIdProvider: updateIdProvider,
            settings: settings
        )

        do {
            try await transfer(over: channel)
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
}

private extension DeviceTransferSenderClient {
    func transfer(over channel: DeviceTransferSenderChannel) async throws {
        let flow = flow
        try await withTimeout(settings.connectTimeout) { try await flow.start() }

        let resumePoint = try await channel.waitForResume()

        for try await step in sequencer.entitySequence(from: resumePoint) {
            try await send(step, over: channel)
        }

        try await flow.sendTransferControl(.senderCompleted)
        try await channel.waitForReceiverCompleted()
    }

    func send(_ step: DeviceTransferSenderStep, over channel: DeviceTransferSenderChannel) async throws {
        switch step {
        case let .started(totalChanges):
            try await flow.sendTransferControl(
                .senderStarted(
                    deviceEncryptionKey: deviceKeyManager.getOrCreatePrivateKey().rawRepresentation,
                    totalChanges: totalChanges
                )
            )
        case let .entities(entities, timePoint):
            try await channel.deliver(entities, timePoint: timePoint)
        case let .roundClosed(timePoint):
            try await channel.deliver([], timePoint: timePoint)
        }
    }
}
