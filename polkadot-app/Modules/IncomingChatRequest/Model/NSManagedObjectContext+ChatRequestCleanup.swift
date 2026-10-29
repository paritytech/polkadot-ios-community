import CoreData
import SubstrateSdk

extension NSManagedObjectContext {
    func deleteChatContactAndChat(for contactId: AccountId) {
        if let contact: CDChatContact = try? first(for: .contact(for: contactId)) {
            delete(contact)
        }

        if let chat: CDChat = try? first(for: .chatWithContact(for: contactId)) {
            delete(chat)
        }
    }

    func chatHasConversation(withContact contactId: AccountId) throws -> Bool {
        guard let chat: CDChat = try first(for: .chatWithContact(for: contactId)) else {
            return false
        }

        let fetchRequest = CDChatMessage.fetchRequest()
        fetchRequest.predicate = .messages(in: chat)

        return try fetch(fetchRequest).contains { message in
            let isUnknownType = Chat.LocalMessage.Content.ContentType(rawValue: UInt8(message.contentType)) == nil
            return isUnknownType || (!message.isSystem && !message.isChatHandshake)
        }
    }
}
