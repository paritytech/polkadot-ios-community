import Foundation
import SubstrateSdk

extension Chat.LocalMessage {
    static func newMessage(to chatId: Chat.Id, content: Content) -> Chat.LocalMessage {
        Chat.LocalMessage(
            messageId: UUID().uuidString,
            chatId: chatId,
            origin: .user,
            creationSource: .localDevice,
            status: .outgoing(.new),
            timestamp: Date().toChatTimestamp(),
            content: content,
            reactions: []
        )
    }

    static func newMessageToPerson(_ accountId: AccountId, content: Content) -> Chat.LocalMessage {
        newMessage(to: Chat.Id.person(accountId), content: content)
    }
}
