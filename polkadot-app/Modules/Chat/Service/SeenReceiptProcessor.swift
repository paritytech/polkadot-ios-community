import CoreData
import Foundation
import SubstrateSdk

final class SeenReceiptProcessor {
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

extension SeenReceiptProcessor: IncomingMessageProcessing {
    func process(messages: [Chat.RemoteMessage], from contact: Chat.Contact) {
        let seenContents = extractSeenReceipts(from: messages)

        guard !seenContents.isEmpty else {
            return
        }

        Task { [weak self] in
            do {
                try await self?.apply(seenContents, from: contact.accountId)
            } catch {
                self?.logger.warning("Failed to apply seen receipt: \(error)")
            }
        }
    }
}

// MARK: - Receive

extension SeenReceiptProcessor {
    func extractSeenReceipts(from messages: [Chat.RemoteMessage]) -> [ChatRemoteMessageContent.SeenContent] {
        messages.compactMap { message in
            guard case let .seen(seenContent) = message.versioned.ensureV1()?.content else {
                return nil
            }

            return seenContent
        }
    }
}

// MARK: - Apply

extension SeenReceiptProcessor {
    func apply(_ contents: [ChatRemoteMessageContent.SeenContent], from accountId: AccountId) async throws {
        let chatId = Chat.Id.person(accountId)

        try await storageFacade.databaseService.performWrite { context in
            let chat: CDChat? = try context.first(for: .chat(for: chatId.rawRepresentation))

            guard let chat else {
                return
            }

            guard let resolvedOrder = try Self.resolvedOrder(for: contents, in: chatId, context: context) else {
                return
            }

            chat.peerSeenOrder = max(chat.peerSeenOrder, resolvedOrder)
        }
    }
}

// MARK: - Private

private extension SeenReceiptProcessor {
    static func resolvedOrder(
        for contents: [ChatRemoteMessageContent.SeenContent],
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
            NSPredicate.messages(withIds: messageIds)
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
