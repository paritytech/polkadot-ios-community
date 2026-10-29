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
}
