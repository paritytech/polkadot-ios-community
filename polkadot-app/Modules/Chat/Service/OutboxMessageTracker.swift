import Foundation
import SubstrateSdk

struct OutboxMessages {
    let contact: Chat.Contact
    let messagesToSend: [Chat.LocalMessage]

    func messageIds() -> Set<Chat.MessageId> {
        Set(messagesToSend.map(\.messageId))
    }
}

protocol OutboxMessageTracking {
    func setContacts(_ newContacts: [AccountId: Chat.Contact])
    func getContact(for accountId: AccountId) -> Chat.Contact?

    func insert(messages: [Chat.LocalMessage])
    var hasMessagesToSend: Bool { get }
    func prepareMessagesToSend() -> [OutboxMessages]
    func markInFlight(messageIds: Set<Chat.MessageId>)

    @discardableResult
    func markSent(messageIds: Set<Chat.MessageId>) -> Set<Chat.MessageId>

    func remove(messageIds: Set<Chat.MessageId>)
    func clear()
}

final class OutboxMessageTracker {
    private var contacts: [AccountId: Chat.Contact] = [:]
    private var messagesToSend: [Chat.MessageId: Chat.LocalMessage] = [:]
    private var inFlightMessages: [Chat.MessageId: Chat.LocalMessage] = [:]
}

private extension OutboxMessageTracker {
    func hasMessage(with messageId: Chat.MessageId) -> Bool {
        messagesToSend[messageId] != nil || inFlightMessages[messageId] != nil
    }
}

extension OutboxMessageTracker: OutboxMessageTracking {
    func setContacts(_ newContacts: [AccountId: Chat.Contact]) {
        let removedAccountIds = Set(contacts.keys).subtracting(Set(newContacts.keys))
        contacts = newContacts

        guard !removedAccountIds.isEmpty else {
            return
        }

        messagesToSend = messagesToSend.filter { message in
            guard let accountId = message.value.contactAccountId else {
                return false
            }

            return !removedAccountIds.contains(accountId)
        }

        inFlightMessages = inFlightMessages.filter { message in
            guard let accountId = message.value.contactAccountId else {
                return false
            }

            return !removedAccountIds.contains(accountId)
        }
    }

    func getContact(for accountId: AccountId) -> Chat.Contact? {
        contacts[accountId]
    }

    func insert(messages: [Chat.LocalMessage]) {
        messages.forEach { message in
            guard !hasMessage(with: message.messageId) else {
                return
            }

            messagesToSend[message.messageId] = message
        }
    }

    var hasMessagesToSend: Bool {
        !messagesToSend.isEmpty
    }

    func prepareMessagesToSend() -> [OutboxMessages] {
        let messages = messagesToSend.values.sorted { message1, message2 in
            ChatMessageComparator.timestampThenOrderComparator(
                message1: message1,
                message2: message2
            )
        }

        let messagesByPeer = messages.reduce(into: [AccountId: [Chat.LocalMessage]]()) { accum, message in
            guard let accountId = message.contactAccountId else {
                return
            }

            let peerMessages = accum[accountId] ?? []
            accum[accountId] = peerMessages + [message]
        }

        return messagesByPeer.compactMap { contactAndMessages in
            guard let contact = contacts[contactAndMessages.key] else {
                return nil
            }

            return OutboxMessages(contact: contact, messagesToSend: contactAndMessages.value)
        }
    }

    func markInFlight(messageIds: Set<Chat.MessageId>) {
        messageIds.forEach { messageId in
            inFlightMessages[messageId] = messagesToSend[messageId]
            messagesToSend[messageId] = nil
        }
    }

    @discardableResult
    func markSent(messageIds: Set<Chat.MessageId>) -> Set<Chat.MessageId> {
        messageIds.reduce(into: Set()) {
            guard inFlightMessages.removeValue(forKey: $1) != nil else {
                return
            }
            $0.insert($1)
        }
    }

    func remove(messageIds: Set<Chat.MessageId>) {
        messageIds.forEach { messageId in
            inFlightMessages[messageId] = nil
            messagesToSend[messageId] = nil
        }
    }

    func clear() {
        contacts = [:]
        messagesToSend = [:]
        inFlightMessages = [:]
    }
}
