import Foundation
import NovaCrypto

public protocol WalletKeypairFactoryProtocol {
    func derivePublicKey() throws -> IRPublicKeyProtocol
    func deriveKeypair() throws -> IRCryptoKeypairProtocol
}
