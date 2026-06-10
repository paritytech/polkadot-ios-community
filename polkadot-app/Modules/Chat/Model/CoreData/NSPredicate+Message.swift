import Foundation
import SubstrateSdk

extension NSPredicate {
    static func localMessages(from chatId: Chat.Id) -> NSPredicate {
        NSPredicate(
            format: "%K == %@",
            #keyPath(CDChatMessage.chat.identifier),
            chatId.rawRepresentation
        )
    }

    static func messages(withIds ids: [String]) -> NSPredicate {
        NSPredicate(
            format: "%K IN %@",
            #keyPath(CDChatMessage.messageId),
            ids
        )
    }

    static func newOutgoingRemoteMessages() -> NSPredicate {
        let statusPredicate = byStatus(Chat.LocalMessage.Status.outgoing(.new))
        let chatTypePredicate = messageByChatType(.person)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [statusPredicate, chatTypePredicate])
    }

    static func newLocalDeviceOutgoingRemoteRichTextMessages() -> NSPredicate {
        let statusPredicate = byStatus(Chat.LocalMessage.Status.outgoing(.new))
        let chatTypePredicate = messageByChatType(.person)
        let contentTypePredicate = messageByContentType(.richText)
        let creationSourcePredicate = byCreationSource(.localDevice)

        let predicates = [
            statusPredicate,
            chatTypePredicate,
            contentTypePredicate,
            creationSourcePredicate
        ]

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func incomingCoinageSendMessages() -> NSPredicate {
        let incomingNewPredicate = byStatus(Chat.LocalMessage.Status.incoming(.new))
        let incomingSeenPredicate = byStatus(Chat.LocalMessage.Status.incoming(.seen))
        let statusPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            incomingNewPredicate,
            incomingSeenPredicate
        ])

        let chatTypePredicate = messageByChatType(.person)
        let contentTypePredicate = messageByContentType(.coinageSend)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            statusPredicate,
            chatTypePredicate,
            contentTypePredicate
        ])
    }

    static func outgoingLocalDeviceCoinageSendMessages() -> NSPredicate {
        let outgoingNewPredicate = byStatus(Chat.LocalMessage.Status.outgoing(.new))
        let outgoingSentPredicate = byStatus(Chat.LocalMessage.Status.outgoing(.sent))
        let statusPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            outgoingNewPredicate,
            outgoingSentPredicate
        ])

        let chatTypePredicate = messageByChatType(.person)
        let contentTypePredicate = messageByContentType(.coinageSend)
        let creationSourcePredicate = byCreationSource(.localDevice)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            statusPredicate,
            chatTypePredicate,
            contentTypePredicate,
            creationSourcePredicate
        ])
    }

    static func incomingRemoteRichTextMessages() -> NSPredicate {
        let incomingNewPredicate = byStatus(Chat.LocalMessage.Status.incoming(.new))
        let incomingSeenPredicate = byStatus(Chat.LocalMessage.Status.incoming(.seen))
        let statusPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            incomingNewPredicate,
            incomingSeenPredicate
        ])

        let chatTypePredicate = messageByChatType(.person)
        let contentTypePredicate = messageByContentType(.richText)

        let predicates = [statusPredicate, chatTypePredicate, contentTypePredicate]

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func newOutgoingChatRequestMessages() -> NSPredicate {
        let statusPredicate = byStatus(Chat.LocalMessage.Status.outgoing(.new))
        let chatTypePredicate = messageByChatType(.person)
        let contentTypePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            messageByContentType(.chatRequest),
            messageByContentType(.versionedChatRequest)
        ])

        let predicates = [statusPredicate, chatTypePredicate, contentTypePredicate]
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func newIncomingMessages(from chatId: Chat.Id) -> NSPredicate {
        let byStatus = byStatus(Chat.LocalMessage.Status.incoming(.new))
        let byContactId = localMessages(from: chatId)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [byContactId, byStatus])
    }

    static func sentLocalDeviceMessages(to chatId: Chat.Id) -> NSPredicate {
        let byStatus = byStatus(Chat.LocalMessage.Status.outgoing(.sent))
        let byContactId = localMessages(from: chatId)
        let byCreationSource = byCreationSource(.localDevice)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            byContactId,
            byStatus,
            byCreationSource
        ])
    }

    static func byStatus(_ status: Chat.LocalMessage.Status) -> NSPredicate {
        NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatMessage.status),
            status.rawValue
        )
    }

    static func byCreationSource(_ creationSource: Chat.LocalMessage.CreationSource) -> NSPredicate {
        NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatMessage.creationSource),
            creationSource.rawValue
        )
    }

    static func messageByChatType(_ chatType: Chat.Id.ChatType) -> NSPredicate {
        NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatMessage.chat.chatType),
            chatType.rawValue
        )
    }

    static func messageByContentType(_ contentType: Chat.LocalMessage.Content.ContentType) -> NSPredicate {
        NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatMessage.contentType),
            contentType.rawValue
        )
    }

    static func messageByContentKey(_ contentKey: String) -> NSPredicate {
        NSPredicate(
            format: "%K == %@",
            #keyPath(CDChatMessage.contentKey),
            contentKey
        )
    }

    static func chatMessage(with remoteMessageId: String) -> NSPredicate {
        NSPredicate(
            format: "%K == %@",
            #keyPath(CDChatMessage.messageId),
            remoteMessageId
        )
    }

    static func siblingGroupMessages(
        groupingId: String,
        excluding entity: CDChatMessage
    ) -> NSPredicate {
        NSPredicate(
            format: "%K == %@ AND SELF != %@",
            #keyPath(CDChatMessage.groupingId),
            groupingId,
            entity
        )
    }

    static func editHistory(for messageId: String) -> NSPredicate {
        let originalMessagePredicate = NSPredicate(
            format: "%K == %@",
            #keyPath(CDChatMessage.messageId),
            messageId
        )

        let editedContentType = Int16(Chat.LocalMessage.Content.ContentType.edited.rawValue)
        let editedMessagesPredicate = NSPredicate(
            format: "%K == %d AND %K == %@",
            #keyPath(CDChatMessage.contentType),
            editedContentType,
            #keyPath(CDChatMessage.contentKey),
            messageId
        )

        return NSCompoundPredicate(orPredicateWithSubpredicates: [originalMessagePredicate, editedMessagesPredicate])
    }
}
