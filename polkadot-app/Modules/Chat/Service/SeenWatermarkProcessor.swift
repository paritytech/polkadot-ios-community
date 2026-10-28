import CoreData
import Foundation
import SubstrateSdk

final class SeenWatermarkProcessor {
    private let storageFacade: StorageFacadeProtocol
    private let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.storageFacade = storageFacade
        self.logger = logger
    }
}

// MARK: - IncomingMessageProcessing

extension SeenWatermarkProcessor: IncomingMessageProcessing {
    func process(messages: [Chat.RemoteMessage], from contact: Chat.Contact) {
        let watermarks = receivedWatermarks(from: messages, contact: contact)

        guard !watermarks.isEmpty else {
            return
        }

        Task { [weak self] in
            do {
                try await self?.apply(watermarks, from: contact.accountId)
            } catch {
                self?.logger.warning("Failed to apply seen watermark: \(error)")
            }
        }
    }
}

// MARK: - Receive

extension SeenWatermarkProcessor {
    func receivedWatermarks(
        from messages: [Chat.RemoteMessage],
        contact: Chat.Contact
    ) -> [ChatRemoteMessageContent.SeenWatermarkContent] {
        guard !contact.isBlocked else {
            return []
        }

        return extractWatermarks(from: messages)
    }
}

// MARK: - Apply

extension SeenWatermarkProcessor {
    func apply(_ contents: [ChatRemoteMessageContent.SeenWatermarkContent], from accountId: AccountId) async throws {
        let chatId = Chat.Id.person(accountId)

        try await storageFacade.databaseService.performWrite { context in
            let chat: CDChat? = try context.first(for: .chat(for: chatId.rawRepresentation))

            guard let chat else {
                return
            }

            guard let watermarkOrder = try Self.watermarkOrder(for: contents, in: chatId, context: context) else {
                return
            }

            chat.peerSeenOrder = max(chat.peerSeenOrder, watermarkOrder)
        }
    }
}

// MARK: - Private

private extension SeenWatermarkProcessor {
    func extractWatermarks(from messages: [Chat.RemoteMessage]) -> [ChatRemoteMessageContent.SeenWatermarkContent] {
        messages.compactMap { message in
            guard case let .seen(watermark) = message.versioned.ensureV1()?.content else {
                return nil
            }

            return watermark
        }
    }

    static func watermarkOrder(
        for contents: [ChatRemoteMessageContent.SeenWatermarkContent],
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> Int64? {
        let orders = try contents.compactMap { content in
            try outgoingOrder(of: [content.messageId], in: chatId, context: context)
                ?? outgoingOrder(atOrBefore: content.timestamp, in: chatId, context: context)
        }
        return orders.max()
    }

    static func outgoingOrder(
        of messageIds: [String],
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> Int64? {
        let request = CDChatMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.localMessages(from: chatId),
            NSPredicate.messages(withIdsIgnoringCase: messageIds)
        ])

        return try context.fetch(request)
            .filter { Chat.LocalMessage.Status(rawValue: $0.status)?.isOutgoing == true }
            .map(\.order)
            .max()
    }

    static func outgoingOrder(
        atOrBefore timestamp: UInt64,
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> Int64? {
        let request = CDChatMessage.fetchRequest()
        request.predicate = NSPredicate.postedOutgoingMessages(
            in: chatId,
            timestampAtOrBefore: Int64(bitPattern: timestamp)
        )
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(CDChatMessage.order), ascending: false)]
        request.fetchLimit = 1

        return try context.fetch(request).first?.order
    }
}
