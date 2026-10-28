import CoreData
import Foundation
import SubstrateSdk

protocol SeenWatermarkDeliveryRecording {
    func recordDelivered(
        _ contents: [ChatRemoteMessageContent.SeenWatermarkContent],
        to peerAccountId: AccountId
    ) async throws
}

final class SeenWatermarkDeliveryRecorder {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        self.storageFacade = storageFacade
    }
}

extension SeenWatermarkDeliveryRecorder: SeenWatermarkDeliveryRecording {
    func recordDelivered(
        _ contents: [ChatRemoteMessageContent.SeenWatermarkContent],
        to peerAccountId: AccountId
    ) async throws {
        let chatId = Chat.Id.person(peerAccountId)

        try await storageFacade.databaseService.performWrite { context in
            guard let chat: CDChat = try context.first(for: .chat(for: chatId.rawRepresentation)) else {
                return
            }

            let deliveredMarks = try Self.deliveredMarks(for: contents, in: chatId, context: context)

            guard let newest = deliveredMarks.max(by: { ($0.order, $0.timestamp) < ($1.order, $1.timestamp) }),
                  (newest.order, newest.timestamp) > (chat.lastSentSeenOrder, chat.lastSentSeenTimestamp) else {
                return
            }

            chat.lastSentSeenOrder = newest.order
            chat.lastSentSeenTimestamp = newest.timestamp
        }
    }
}

private extension SeenWatermarkDeliveryRecorder {
    static func deliveredMarks(
        for contents: [ChatRemoteMessageContent.SeenWatermarkContent],
        in chatId: Chat.Id,
        context: NSManagedObjectContext
    ) throws -> [(order: Int64, timestamp: Int64)] {
        let request = CDChatMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.localMessages(from: chatId),
            NSPredicate.messages(withIdsIgnoringCase: contents.map(\.messageId))
        ])

        let incomingEntities = try context.fetch(request).filter {
            Chat.LocalMessage.Status(rawValue: $0.status)?.isIncoming == true
        }

        return contents.compactMap { content in
            incomingEntities.first { $0.messageId?.lowercased() == content.messageId.lowercased() }.map {
                (order: $0.order, timestamp: Int64(bitPattern: content.timestamp))
            }
        }
    }
}
