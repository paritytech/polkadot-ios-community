import Foundation
import SubstrateSdk
import Operation_iOS
import KeyDerivation
import StructuredConcurrency

protocol AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging
}

final class AttachmentsSenderProvider {
    let contactsStorageService: ContactsLocalStorageServicing

    init(
        contactsStorageService: ContactsLocalStorageServicing = ContactsLocalStorageService()
    ) {
        self.contactsStorageService = contactsStorageService
    }
}

extension AttachmentsSenderProvider: AttachmentsSenderProviding {
    func getWallet(for chatId: Chat.Id) async throws -> WalletManaging {
        guard let accountId = chatId.accountId else {
            return DynamicDerivedWallet(derivationPath: WalletDerivationPath.main)
        }

        let contact = try await contactsStorageService
            .getContact(by: accountId)
            .asyncExecute()

        let signKeyId = contact?.ownKeyId.signKeyId ?? WalletDerivationPath.main

        return DynamicDerivedWallet(derivationPath: signKeyId)
    }
}
