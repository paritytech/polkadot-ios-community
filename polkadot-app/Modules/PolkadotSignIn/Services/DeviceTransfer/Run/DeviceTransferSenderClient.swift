import Foundation
import FoundationExt
import StructuredConcurrency

final class DeviceTransferSenderClient: DeviceTransferClientProtocol {
    private let flow: any DevicePeerConnectionFlowing
    private let collector: DeviceTransferChangesCollecting
    private let deviceKeyManager: DeviceEncryptionKeyManaging
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let dateProvider: any DateProviding
    private let settings: DeviceTransferSenderSettings
    private let logger: LoggerProtocol

    init(
        flow: any DevicePeerConnectionFlowing,
        collector: DeviceTransferChangesCollecting,
        dependencies: DeviceTransferSenderDependencies,
        settings: DeviceTransferSenderSettings = DeviceTransferSenderSettings()
    ) {
        self.flow = flow
        self.collector = collector
        deviceKeyManager = dependencies.deviceKeyManager
        updateIdProvider = dependencies.updateIdProvider
        dateProvider = dependencies.dateProvider
        logger = dependencies.logger
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

private extension DeviceTransferSenderClient {
    func transfer(over channel: DeviceTransferSenderChannel) async throws {
        let flow = flow
        try await withTimeout(settings.connectTimeout) { try await flow.start() }

        let resumePoint = try await channel.waitForResume()
        var round = await DeviceTransferRound.first(from: resumePoint, end: currentTimePoint())
        var state = try await collector.collectStateEntities(since: nil)

        try await sendStarted(state: state, round: round)

        while try await send(round, state: state, over: channel) > 0 {
            round = await round.next(end: currentTimePoint())
            state = try await collector.collectStateEntities(since: round.cutoff)
        }

        try await flow.sendTransferControl(.senderCompleted)
        try await channel.waitForReceiverCompleted()
    }
}

struct DeviceTransferSenderDependencies {
    let deviceKeyManager: DeviceEncryptionKeyManaging
    let updateIdProvider: DeviceSyncUpdateIdProviding
    let dateProvider: any DateProviding
    let logger: LoggerProtocol
}

private struct DeviceTransferRound {
    let cutoff: UInt64?
    /// `nil` for the first round, so a legacy message stamped ahead of this clock is still sent once.
    let modifiedUpTo: UInt64?
    let end: UInt64

    static func first(from cutoff: UInt64?, end: UInt64) -> Self {
        Self(cutoff: cutoff, modifiedUpTo: nil, end: end)
    }

    func next(end: UInt64) -> Self {
        Self(cutoff: self.end, modifiedUpTo: end, end: end)
    }
}

private extension DeviceTransferSenderClient {
    func currentTimePoint() async -> UInt64 {
        await dateProvider.read().toChatTimestamp()
    }

    func sendStarted(state: [Chat.DeviceSyncEntity], round: DeviceTransferRound) async throws {
        let messageCount = try await collector.countMessages(since: round.cutoff, modifiedUpTo: round.modifiedUpTo)
        let total = state.reduce(messageCount) { $0 + $1.itemCount }

        try await flow.sendTransferControl(
            .senderStarted(
                deviceEncryptionKey: deviceKeyManager.getOrCreatePrivateKey().rawRepresentation,
                totalChanges: UInt32(clamping: total)
            )
        )
    }

    func send(
        _ round: DeviceTransferRound,
        state: [Chat.DeviceSyncEntity],
        over channel: DeviceTransferSenderChannel
    ) async throws -> Int {
        let timePoint = round.cutoff ?? 0
        var itemCount = state.reduce(0) { $0 + $1.itemCount }

        if !state.isEmpty {
            try await channel.deliver(state, timePoint: timePoint)
        }

        var cursor: DeviceTransferMessageCursor?
        repeat {
            let page = try await collector.collectMessagePage(
                since: round.cutoff,
                modifiedUpTo: round.modifiedUpTo,
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
