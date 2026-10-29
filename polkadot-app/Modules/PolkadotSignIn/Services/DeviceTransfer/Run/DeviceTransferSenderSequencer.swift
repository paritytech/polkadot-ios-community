import Foundation
import FoundationExt

enum DeviceTransferSenderStep {
    case started(totalChanges: UInt32)
    case entities([Chat.DeviceSyncEntity], timePoint: UInt64)
    case roundClosed(timePoint: UInt64)
}

protocol DeviceTransferSenderSequencing {
    /// Pull-based: the next step is collected only when asked for, so a page waits for the previous one's acks.
    func entitySequence(from checkpoint: UInt64?) -> AsyncThrowingStream<DeviceTransferSenderStep, Error>
}

/// Rounds repeat from the previous round's end until one carries nothing. Within a round chat state comes first,
/// so chats exist before their messages, and coinage state last, so claims find their messages.
final class DeviceTransferSenderSequencer {
    static let defaultMessagePageSize = 200

    private enum Phase {
        case starting
        case nextRound
        case chatState
        case messages(after: DeviceTransferMessageCursor?)
        case coinageState
        case closing
        case finished
    }

    private struct Round {
        let cutoff: UInt64?
        /// `nil` for the first round, so a legacy message stamped ahead of this clock is still sent once.
        let modifiedUpTo: UInt64?
        let end: UInt64

        var timePoint: UInt64 { cutoff ?? 0 }
    }

    private let collector: DeviceTransferChangesCollecting
    private let dateProvider: any DateProviding
    private let messagePageSize: Int
    private let logger: LoggerProtocol

    private var phase = Phase.finished
    private var round = Round(cutoff: nil, modifiedUpTo: nil, end: 0)
    private var firstRoundState: (chat: [Chat.DeviceSyncEntity], coinage: [Chat.DeviceSyncEntity])?
    private var itemCount = 0

    init(
        collector: DeviceTransferChangesCollecting,
        dateProvider: any DateProviding,
        messagePageSize: Int = DeviceTransferSenderSequencer.defaultMessagePageSize,
        logger: LoggerProtocol
    ) {
        self.collector = collector
        self.dateProvider = dateProvider
        self.messagePageSize = messagePageSize
        self.logger = logger
    }
}

extension DeviceTransferSenderSequencer: DeviceTransferSenderSequencing {
    func entitySequence(from checkpoint: UInt64?) -> AsyncThrowingStream<DeviceTransferSenderStep, Error> {
        round = Round(cutoff: checkpoint, modifiedUpTo: nil, end: 0)
        phase = .starting

        return AsyncThrowingStream { [self] in try await nextStep() }
    }
}

private extension DeviceTransferSenderSequencer {
    func nextStep() async throws -> DeviceTransferSenderStep? {
        while true {
            if let step = try await advance() {
                return step
            }

            if case .finished = phase {
                return nil
            }
        }
    }

    func advance() async throws -> DeviceTransferSenderStep? {
        switch phase {
        case .starting:
            return try await startFirstRound()
        case .nextRound:
            let end = await currentTimePoint()
            round = Round(cutoff: round.end, modifiedUpTo: end, end: end)
            itemCount = 0
            phase = .chatState
            return nil
        case .chatState:
            phase = .messages(after: nil)
            return try await entitiesStep(chatState())
        case let .messages(cursor):
            return try await messagesStep(after: cursor)
        case .coinageState:
            phase = .closing
            return try await entitiesStep(coinageState())
        case .closing:
            logger.debug("Device transfer round up to \(round.end) carried \(itemCount) item(s)")
            phase = itemCount > 0 ? .nextRound : .finished
            return .roundClosed(timePoint: round.end)
        case .finished:
            return nil
        }
    }

    func startFirstRound() async throws -> DeviceTransferSenderStep {
        round = await Round(cutoff: round.cutoff, modifiedUpTo: nil, end: currentTimePoint())
        itemCount = 0

        let chat = try await collector.collectChatStateEntities(since: nil)
        let coinage = try await collector.collectCoinageStateEntities(since: nil)
        let messageCount = try await collector.countMessages(since: round.cutoff, modifiedUpTo: round.modifiedUpTo)
        firstRoundState = (chat, coinage)
        phase = .chatState

        let total = (chat + coinage).reduce(messageCount) { $0 + $1.itemCount }
        return .started(totalChanges: UInt32(clamping: total))
    }

    func chatState() async throws -> [Chat.DeviceSyncEntity] {
        if let chat = firstRoundState?.chat {
            return chat
        }
        return try await collector.collectChatStateEntities(since: round.cutoff)
    }

    func coinageState() async throws -> [Chat.DeviceSyncEntity] {
        defer { firstRoundState = nil }

        if let coinage = firstRoundState?.coinage {
            return coinage
        }
        return try await collector.collectCoinageStateEntities(since: round.cutoff)
    }

    func messagesStep(after cursor: DeviceTransferMessageCursor?) async throws -> DeviceTransferSenderStep? {
        let page = try await collector.collectMessagePage(
            since: round.cutoff,
            modifiedUpTo: round.modifiedUpTo,
            after: cursor,
            limit: messagePageSize
        )

        phase = page.nextCursor.map { .messages(after: $0) } ?? .coinageState
        return page.messages.isEmpty ? nil : entitiesStep([.messages(page.messages)])
    }

    func entitiesStep(_ entities: [Chat.DeviceSyncEntity]) -> DeviceTransferSenderStep? {
        guard !entities.isEmpty else { return nil }

        itemCount += entities.reduce(0) { $0 + $1.itemCount }
        return .entities(entities, timePoint: round.timePoint)
    }

    func currentTimePoint() async -> UInt64 {
        await dateProvider.read().toChatTimestamp()
    }
}
