import Foundation

extension Chat.Contact.Own {
    static func main() -> Chat.Contact.Own {
        Chat.Contact.Own(
            signKeyId: WalletDerivationPath.main,
            encryptionKeyId: ChatDerivationPath.mainChat.rawValue
        )
    }

    static func sso() -> Chat.Contact.Own {
        Chat.Contact.Own(
            signKeyId: WalletDerivationPath.main,
            encryptionKeyId: ChatDerivationPath.sso.rawValue
        )
    }

    static func gameCandidate() -> Chat.Contact.Own {
        Chat.Contact.Own(
            signKeyId: WalletDerivationPath.candidate,
            encryptionKeyId: gameEncryptionKeyId()
        )
    }

    static func gameExternal() -> Chat.Contact.Own {
        Chat.Contact.Own(
            signKeyId: WalletDerivationPath.score,
            encryptionKeyId: gameEncryptionKeyId()
        )
    }

    static func gameEncryptionKeyId() -> String {
        ChatDerivationPath.gameChat.rawValue
    }

    static func allPossibleIds() -> Set<Chat.Contact.Own> {
        [main(), sso(), gameCandidate(), gameExternal()]
    }
}
