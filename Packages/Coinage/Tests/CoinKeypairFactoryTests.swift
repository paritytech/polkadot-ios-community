import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
@testable import Coinage

struct CoinKeypairFactoryTests {
    private let mockEntropyManager: MockEntropyManager
    private let factory: CoinKeypairFactory

    init() {
        mockEntropyManager = MockEntropyManager()
        factory = CoinKeypairFactory(entropyManager: mockEntropyManager)
    }

    @Test("Successfully creates public key when entropy is present")
    func derivePublicKeySuccess() throws {
        let validEntropy = Data(repeating: 0x01, count: 32)
        try mockEntropyManager.createRootEntropy(validEntropy)

        let coin = Coin(exponent: 0, derivationIndex: 1, age: nil, state: .available)
        let publicKey = try factory.derivePublicKey(for: coin)

        #expect(publicKey.count == 32)
    }

    @Test("Throws error when entropy is missing")
    func derivePublicKeyMissingEntropy() throws {
        let coin = Coin(exponent: 0, derivationIndex: 1, age: nil, state: .available)

        #expect(throws: RootEntropyManagerError.noEntropyFound) {
            _ = try factory.derivePublicKey(for: coin)
        }
    }

    @Test("Derives deterministic keys for same entropy and index")
    func deterministicDerivation() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let manager2 = MockEntropyManager(entropy: entropy)
        let factory2 = CoinKeypairFactory(entropyManager: manager2)

        let coin1 = Coin(exponent: 0, derivationIndex: 5, age: nil, state: .available)
        let coin2 = Coin(exponent: 0, derivationIndex: 5, age: nil, state: .available)

        let key1 = try factory.derivePublicKey(for: coin1)
        let key2 = try factory2.derivePublicKey(for: coin2)

        #expect(key1 == key2)
    }

    @Test("Derives different keys for different indices")
    func differentIndicesProduceDifferentKeys() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let coin1 = Coin(exponent: 0, derivationIndex: 1, age: nil, state: .available)
        let coin2 = Coin(exponent: 0, derivationIndex: 2, age: nil, state: .available)

        let key1 = try factory.derivePublicKey(for: coin1)
        let key2 = try factory.derivePublicKey(for: coin2)

        #expect(key1 != key2)
    }

    @Test("Base derivation path is correct")
    func derivationPathCorrectness() {
        let coin = Coin(
            exponent: 0,
            derivationIndex: 123,
            age: nil,
            state: .available
        )

        let path = factory.derivationPath(for: coin)
        #expect(path == "//pps//coin//123")
    }
}
