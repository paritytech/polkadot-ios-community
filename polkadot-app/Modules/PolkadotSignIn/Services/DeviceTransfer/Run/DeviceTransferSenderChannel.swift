import Foundation

struct DeviceTransferSenderSettings {
    var messagePageSize = 200
    var connectTimeout: Duration = .seconds(45)
    var responseTimeout: Duration = .seconds(30)
    /// The receiver pulls files before confirming, so this wait covers the whole file phase.
    var completionTimeout: Duration = DeviceTransferConstants.runIdleTimeout
    var entityChunker = DeviceSyncEntityChunker()
    var sleep: DeviceSyncSleep = liveDeviceSyncSleep
}

struct DeviceTransferSenderChannel {
    private let flow: any DevicePeerConnectionFlowing
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let entityChunker: DeviceSyncEntityChunker
    private let completionTimeout: Duration
    private var events: DeviceTransferEventStream

    init(
        flow: any DevicePeerConnectionFlowing,
        updateIdProvider: DeviceSyncUpdateIdProviding,
        settings: DeviceTransferSenderSettings
    ) async {
        self.flow = flow
        self.updateIdProvider = updateIdProvider
        entityChunker = settings.entityChunker
        completionTimeout = settings.completionTimeout
        events = await DeviceTransferEventStream(
            flow: flow,
            timeout: settings.responseTimeout,
            sleep: settings.sleep
        )
    }

    func close() {
        events.close()
    }

    mutating func waitForResume() async throws -> UInt64? {
        try await events.waitForControl { control in
            guard case let .resume(timePoint) = control else { return nil }
            return .some(timePoint)
        }
    }

    mutating func waitForReceiverCompleted() async throws {
        try await events.waitForControl(within: completionTimeout) { $0 == .receiverCompleted ? () : nil }
    }

    /// Sends the entities as one or more updates and returns once the receiver has acknowledged all of them.
    /// Empty entities still produce one update, which carries a round's closing time point.
    mutating func deliver(_ entities: [Chat.DeviceSyncEntity], timePoint: UInt64) async throws {
        let batches = entities.isEmpty ? [[]] : try entityChunker.chunk(entities)
        var pendingIds = Set<UInt32>()

        for batch in batches {
            let update = Chat.DeviceSyncUpdate(id: updateIdProvider.nextId(), entities: batch, timePoint: timePoint)
            try await flow.sendUpdate(update)
            pendingIds.insert(update.id)
        }

        while !pendingIds.isEmpty {
            if case let .ack(id) = try await events.next() {
                pendingIds.remove(id)
            }
        }
    }
}
