import CryptoKit
import Foundation
import MessageExchangeKit
import Testing

@testable import polkadot_app

@Suite("W3S ECIES round-trip")
struct W3sEncryptionTests {
    @Test("iOS ECIES wire format decrypts back to the same plaintext with the merchant's key")
    func eciesRoundTrip() throws {
        // 1. Simulated merchant keypair — the iOS app sees only the compressed public key.
        let merchantPrivate = P256.KeyAgreement.PrivateKey()
        let merchantCompressed = merchantPrivate.publicKey.compressedRepresentation
        let merchantPublic = try P256.KeyAgreement.PublicKey(compressedRepresentation: merchantCompressed)

        // 2. iOS side: generate ephemeral, encrypt plaintext exactly as W3sStatementSubmitter does.
        let ephemeralPrivate = P256.KeyAgreement.PrivateKey()
        let factory = P256AESEncryptorFactory(privateKey: ephemeralPrivate)
        let encryptor = try factory.makeEncryptor(remotePublicKey: merchantPublic.x963Representation)

        let plaintext = Data("hello W3S merchant".utf8)
        let ciphertext = try encryptor.encrypt(plaintext)

        // 3. Merchant side: derive the shared secret with the ephemeral pubkey we sent,
        //    re-build the symmetric encryptor, decrypt.
        let ephemeralPublicReceived = try P256.KeyAgreement.PublicKey(
            x963Representation: factory.localPublicKey
        )
        let merchantShared = try merchantPrivate.sharedSecretFromKeyAgreement(with: ephemeralPublicReceived)
        let merchantEncryptor = AESEncryptor(sharedSecret: merchantShared)
        let recovered = try merchantEncryptor.decrypt(ciphertext)

        #expect(recovered == plaintext)
    }

    @Test("Ephemeral public key emitted by P256AESEncryptorFactory is the 65-byte uncompressed form")
    func ephemeralIsUncompressed() {
        let ephemeralPrivate = P256.KeyAgreement.PrivateKey()
        let factory = P256AESEncryptorFactory(privateKey: ephemeralPrivate)
        let pubKey = factory.localPublicKey

        #expect(pubKey.count == 65)
        #expect(pubKey.first == 0x04, "uncompressed P256 keys begin with the 0x04 octet")
    }

    @Test("Ciphertext layout is IV(12) ‖ AEAD ciphertext ‖ tag(16)")
    func ciphertextLayout() throws {
        let merchantPrivate = P256.KeyAgreement.PrivateKey()
        let factory = P256AESEncryptorFactory(privateKey: P256.KeyAgreement.PrivateKey())
        let encryptor = try factory.makeEncryptor(remotePublicKey: merchantPrivate.publicKey.x963Representation)

        let plaintext = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) })
        let ciphertext = try encryptor.encrypt(plaintext)
        // AES-GCM 12-byte nonce + len(plaintext) + 16-byte tag.
        #expect(ciphertext.count == 12 + plaintext.count + 16)
    }
}
