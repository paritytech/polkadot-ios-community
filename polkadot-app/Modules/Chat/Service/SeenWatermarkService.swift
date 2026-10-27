import CoreData
import Foundation

protocol SeenWatermarkSending {
    func sendWatermark(for chatId: Chat.Id) async throws
}

final class SeenWatermarkService {
    private let storageFacade: StorageFacadeProtocol
    private let sender: ChatDirectMessageSending

    init(storageFacade: StorageFacadeProtocol, sender: ChatDirectMessageSending) {
        self.storageFacade = storageFacade
        self.sender = sender
    }
}

extension SeenWatermarkService: SeenWatermarkSending {
    func sendWatermark(for chatId: Chat.Id) async throws {
        guard case let .person(accountId) = chatId else {
            return
        }

        let watermark = try await storageFacade.databaseService.performRead { context in
            try Self.fetchWatermark(in: chatId, context: context)
        }

        guard let watermark else {
            return
        }

        let content = ChatRemoteMessageContent.seen(
            .init(messageId: watermark.messageId, timestamp: watermark.timestamp)
        )

        sender.sendDirectly(Chat.RemoteMessage.newMessage(with: content), to: accountId)
    }
}

private extension SeenWatermarkService {
    static func fetchWatermark(
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> Chat.LocalMessage? {
        let request = CDChatMessage.fetchRequest()
        request.predicate = NSPredicate.seenWatermarkCandidates(in: chatId)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(CDChatMessage.order), ascending: false),
            NSSortDescriptor(key: #keyPath(CDChatMessage.timestamp), ascending: false)
        ]
        request.fetchLimit = 1

        return try context.fetch(request).first.map {
            try ChatMessageEntityMapper().transform(entity: $0)
        }
    }
}
