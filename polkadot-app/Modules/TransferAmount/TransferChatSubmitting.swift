import Coinage
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SDKLogger

protocol TransferChatSubmitting {
    /// When `true`, the interactor propagates `sendChatMessage` errors instead
    /// of swallowing them. Default `false` matches best-effort chat-memo delivery.
    var isFailureFatal: Bool { get }

    func sendChatMessage(_ memo: TransferMemo, to recipient: AccountId) async throws
}

extension TransferChatSubmitting {
    var isFailureFatal: Bool { false }
}

final class ContactChatSubmitter: TransferChatSubmitting {
    private let chatContactsProvider: ContactsLocalStorageServicing
    private let createMessageFactory: LocalMessageCreatingOperationMaking
    private let logger: SDKLoggerProtocol?

    init(
        chatContactsProvider: ContactsLocalStorageServicing,
        createMessageFactory: LocalMessageCreatingOperationMaking,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.chatContactsProvider = chatContactsProvider
        self.createMessageFactory = createMessageFactory
        self.logger = logger
    }

    func sendChatMessage(_ memo: TransferMemo, to recipient: AccountId) async throws {
        let optContact = try await chatContactsProvider.getContact(by: recipient).asyncExecute()

        guard let contact = optContact.flatMap({ $0 }) else {
            logger?.debug("No chat contact found within timeout — skipping message")
            return
        }

        let operation = createMessageFactory.createTransfer(
            to: Chat.Id.person(contact.accountId),
            memo: memo
        )
        try await CompoundOperationWrapper(targetOperation: operation).asyncExecute()
    }
}

struct NoChatSubmitter: TransferChatSubmitting {
    func sendChatMessage(_: TransferMemo, to _: AccountId) async throws {}
}
