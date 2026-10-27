import CoreData
import Foundation
import os

protocol SeenWatermarkSending {
    @discardableResult
    func scheduleWatermark(for chatId: Chat.Id) -> Task<Void, Never>
}

final class SeenWatermarkService {
    private static let debounceDelay: Duration = .seconds(1)

    private let storageFacade: StorageFacadeProtocol
    private let sender: ChatDirectMessageSending
    private let clock: any Clock<Duration>
    private let logger: LoggerProtocol
    private let pendingTasks = OSAllocatedUnfairLock(initialState: [Chat.Id: Task<Void, Never>]())

    init(
        storageFacade: StorageFacadeProtocol,
        sender: ChatDirectMessageSending,
        clock: any Clock<Duration> = ContinuousClock(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.storageFacade = storageFacade
        self.sender = sender
        self.clock = clock
        self.logger = logger
    }
}

extension SeenWatermarkService: SeenWatermarkSending {
    @discardableResult
    func scheduleWatermark(for chatId: Chat.Id) -> Task<Void, Never> {
        let task = Task {
            await sendAfterDebounce(for: chatId)
        }

        pendingTasks.withLock { tasks in
            tasks.updateValue(task, forKey: chatId)?.cancel()
        }

        return task
    }
}

private extension SeenWatermarkService {
    func sendAfterDebounce(for chatId: Chat.Id) async {
        guard await (try? clock.sleep(for: Self.debounceDelay)) != nil else {
            return
        }

        do {
            try await sendIfAdvanced(for: chatId)
        } catch {
            logger.error("Failed to send seen watermark: \(error)")
        }
    }

    func sendIfAdvanced(for chatId: Chat.Id) async throws {
        guard case let .person(accountId) = chatId else {
            return
        }

        let state = try await storageFacade.databaseService.performRead { context in
            try Self.fetchState(in: chatId, context: context)
        }

        guard let state,
              (state.order, state.timestamp) > (state.lastSentOrder, state.lastSentTimestamp),
              !Task.isCancelled else {
            return
        }

        let content = ChatRemoteMessageContent.seen(
            .init(messageId: state.messageId, timestamp: UInt64(bitPattern: state.timestamp))
        )
        sender.sendDirectly(Chat.RemoteMessage.newMessage(with: content), to: accountId)
    }

    static func fetchState(
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> SeenWatermarkState? {
        let request = CDChatMessage.fetchRequest()
        request.predicate = NSPredicate.seenWatermarkCandidates(in: chatId)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(CDChatMessage.order), ascending: false),
            NSSortDescriptor(key: #keyPath(CDChatMessage.timestamp), ascending: false)
        ]
        request.fetchLimit = 1

        guard let watermark = try context.fetch(request).first, let messageId = watermark.messageId else {
            return nil
        }

        let chat: CDChat? = try context.first(for: .chat(for: chatId.rawRepresentation))

        return SeenWatermarkState(
            messageId: messageId,
            order: watermark.order,
            timestamp: watermark.timestamp,
            lastSentOrder: chat?.lastSentSeenOrder ?? 0,
            lastSentTimestamp: chat?.lastSentSeenTimestamp ?? 0
        )
    }
}

private struct SeenWatermarkState {
    let messageId: String
    let order: Int64
    let timestamp: Int64
    let lastSentOrder: Int64
    let lastSentTimestamp: Int64
}
