import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// Counts incoming-new badge messages without materializing chat or message model graphs.
///
/// This service is used by the notification extension, where work happens during a short-lived
/// push-processing window. Use a count operation here to avoid mapping `Chat.LocalModel` and
/// faulting every message in each unread chat through `ChatModelMapper.nonReactionUnreadCount`.
///
/// The count mirrors the app display badge semantics:
/// - incoming `.new` messages are counted.
/// - only messages attached to a chat are considered.
/// - reaction update messages are excluded from the badge count.
/// - system messages are excluded from the badge count.
final class UnreadMessageCountService {
    private let databaseService: CoreDataServiceProtocol

    init(
        databaseService: CoreDataServiceProtocol = UserDataStorageFacade.shared.databaseService
    ) {
        self.databaseService = databaseService
    }

    func totalUnreadBadgeMessageCount() async throws -> Int {
        let repository = CoreDataRepository<Chat.LocalMessage, CDChatMessage>(
            databaseService: databaseService,
            mapper: AnyCoreDataMapper(ChatMessageEntityMapper()),
            filter: Self.badgeCountPredicate()
        )

        return try await repository.fetchCountOperation().asyncExecute()
    }
}

private extension UnreadMessageCountService {
    // Keep this aligned with `Chat.LocalMessage.Content.ContentType.isReaction` and `.isSystem`.
    static let badgeExcludedContentTypes = [
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.reacted.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.reactionRemoved.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.token.rawValue))
    ]
}

extension UnreadMessageCountService {
    static func badgeCountPredicate() -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            .byStatus(.incoming(.new)),
            NSPredicate(format: "%K != nil", #keyPath(CDChatMessage.chat)),
            NSPredicate(format: "NOT (%K IN %@)", #keyPath(CDChatMessage.contentType), badgeExcludedContentTypes)
        ])
    }
}
