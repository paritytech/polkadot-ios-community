import Foundation
import FoundationExt
import StructuredConcurrency

/// Old phone's side of one transfer connection. It keeps no state between connections: the receiver's
/// `resume` point says where to start, and re-sent data is safe to apply again.
///
/// Data goes in rounds. A round sends what changed after its cutoff, every update stamped with the cutoff, and
/// closes with an empty update stamped with the round's end. The receiver's checkpoint therefore only moves once a
/// whole round is applied. Rounds repeat from the previous end until one finds nothing.
struct DeviceTransferSenderExchange {
    private let flow: any DevicePeerConnectionFlowing
    private let collector: DeviceTransferChangesCollecting
    private let deviceEncryptionKey: Data
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let dateProvider: any DateProviding
    private let settings: DeviceTransferSenderSettings
    private let logger: LoggerProtocol

    init(
        flow: any DevicePeerConnectionFlowing,
        collector: DeviceTransferChangesCollecting,
        deviceEncryptionKey: Data,
        dependencies: DeviceTransferSenderDependencies,
        settings: DeviceTransferSenderSettings = DeviceTransferSenderSettings()
    ) {
        self.flow = flow
        self.collector = collector
        self.deviceEncryptionKey = deviceEncryptionKey
        updateIdProvider = dependencies.updateIdProvider
        dateProvider = dependencies.dateProvider
        logger = dependencies.logger
        self.settings = settings
    }

    func run() async throws {
        var channel = await DeviceTransferSenderChannel(
            flow: flow,
            updateIdProvider: updateIdProvider,
            settings: settings
        )
        defer { channel.close() }

        let flow = flow
        try await withTimeout(settings.connectTimeout) { try await flow.start() }

        let resumePoint = try await channel.waitForResume()
        var round = await DeviceTransferRound.first(from: resumePoint, end: currentTimePoint())
        var state = try await collector.collectStateEntities(since: nil)

        try await sendStarted(state: state, round: round)

        while try await send(round, state: state, over: &channel) > 0 {
            round = await round.next(end: currentTimePoint())
            state = try await collector.collectStateEntities(since: round.cutoff)
        }

        try await flow.sendTransferControl(.senderCompleted)
        try await channel.waitForReceiverCompleted()
    }
}

struct DeviceTransferSenderDependencies {
    let updateIdProvider: DeviceSyncUpdateIdProviding
    let dateProvider: any DateProviding
    let logger: LoggerProtocol
}

private struct DeviceTransferRound {
    let cutoff: UInt64?
    /// `nil` for the first round, so a legacy message stamped ahead of this clock is still sent once.
    let bound: UInt64?
    let end: UInt64

    static func first(from cutoff: UInt64?, end: UInt64) -> Self {
        Self(cutoff: cutoff, bound: nil, end: end)
    }

    func next(end: UInt64) -> Self {
        Self(cutoff: self.end, bound: end, end: end)
    }
}

private extension DeviceTransferSenderExchange {
    func currentTimePoint() async -> UInt64 {
        await dateProvider.read().toChatTimestamp()
    }

    func sendStarted(state: [Chat.DeviceSyncEntity], round: DeviceTransferRound) async throws {
        let messageCount = try await collector.countMessages(since: round.cutoff, upTo: round.bound)
        let total = state.reduce(messageCount) { $0 + $1.itemCount }

        try await flow.sendTransferControl(
            .senderStarted(deviceEncryptionKey: deviceEncryptionKey, totalChanges: UInt32(clamping: total))
        )
    }

    /// Returns how many items the round carried.
    func send(
        _ round: DeviceTransferRound,
        state: [Chat.DeviceSyncEntity],
        over channel: inout DeviceTransferSenderChannel
    ) async throws -> Int {
        let timePoint = round.cutoff ?? 0
        var itemCount = state.reduce(0) { $0 + $1.itemCount }

        if !state.isEmpty {
            try await channel.deliver(state, timePoint: timePoint)
        }

        var cursor: String?
        repeat {
            let page = try await collector.collectMessagePage(
                since: round.cutoff,
                upTo: round.bound,
                after: cursor,
                limit: settings.messagePageSize
            )

            if !page.messages.isEmpty {
                try await channel.deliver([.messages(page.messages)], timePoint: timePoint)
                itemCount += page.messages.count
            }

            cursor = page.nextCursor
        } while cursor != nil

        try await channel.deliver([], timePoint: round.end)
        logger.debug("Device transfer round up to \(round.end) sent \(itemCount) item(s)")

        return itemCount
    }
}
