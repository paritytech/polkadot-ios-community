import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import BandersnatchApi
@testable import Coinage

struct VoucherEntropyDerivingTests {
    private let seed = Data(repeating: 0x01, count: 32)

    @Test("Derives entropy successfully for valid all-hard paths")
    func derivesEntropyValidPath() throws {
        let deriver = VoucherEntropyDeriving(path: "//hard1//hard2")
        let entropy = try deriver.deriveEntropy(from: seed)

        #expect(entropy.count == 32)
    }

    @Test("Throws an error when path contains soft junctions")
    func derivesEntropyInvalidPath() throws {
        // VoucherEntropyDeriving expects only hard junctions (//)
        let deriver = VoucherEntropyDeriving(path: "//hard1/soft2")

        #expect(throws: VoucherEntropyDerivingError.invalidDerivationPath) {
            try deriver.deriveEntropy(from: seed)
        }
    }

    @Test("Throws an error for invalid junction format")
    func derivesEntropyInvalidFormat() throws {
        let deriver = VoucherEntropyDeriving(path: "invalid")

        // SubstrateJunctionFactory throws for paths not starting with / or //
        #expect(throws: Error.self) {
            try deriver.deriveEntropy(from: seed)
        }
    }
}

struct VoucherKeypairFactoryTests {
    private let mockEntropyManager: MockEntropyManager
    private let factory: VoucherKeypairFactory

    init() {
        mockEntropyManager = MockEntropyManager()
        factory = VoucherKeypairFactory(entropyManager: mockEntropyManager)
    }

    @Test("Successfully creates public key when entropy and valid model are present")
    func derivePublicKeySuccess() throws {
        let validEntropy = Data(repeating: 0x01, count: 32)
        try mockEntropyManager.createRootEntropy(validEntropy)

        let voucher = Voucher(
            exponent: 0,
            derivationIndex: 1,
            allocatedAt: Date(),
            readyAt: Date()
        )

        let publicKey = try factory.derivePublicKey(for: voucher)

        #expect(!publicKey.isEmpty)
    }

    @Test("Throws error when entropy is missing")
    func derivePublicKeyMissingEntropy() throws {
        let voucher = Voucher(
            exponent: 0,
            derivationIndex: 1,
            allocatedAt: Date(),
            readyAt: Date()
        )

        #expect(throws: RootEntropyManagerError.noEntropyFound) {
            try factory.derivePublicKey(for: voucher)
        }
    }

    @Test("Derives deterministic keys for same entropy and index")
    func deterministicDerivation() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let manager2 = MockEntropyManager(entropy: entropy)
        let factory2 = VoucherKeypairFactory(entropyManager: manager2)

        let voucher1 = Voucher(
            exponent: 0,
            derivationIndex: 10,
            allocatedAt: Date(),
            readyAt: Date()
        )
        let voucher2 = Voucher(
            exponent: 0,
            derivationIndex: 10,
            allocatedAt: Date(),
            readyAt: Date()
        )

        let key1 = try factory.derivePublicKey(for: voucher1)
        let key2 = try factory2.derivePublicKey(for: voucher2)

        #expect(key1 == key2)
    }

    @Test("Derives different keys for different indices")
    func differentIndicesProduceDifferentKeys() throws {
        let entropy = Data(repeating: 0xAB, count: 32)
        try mockEntropyManager.createRootEntropy(entropy)

        let voucher1 = Voucher(
            exponent: 0,
            derivationIndex: 1,
            allocatedAt: Date(),
            readyAt: Date()
        )
        let voucher2 = Voucher(
            exponent: 0,
            derivationIndex: 2,
            allocatedAt: Date(),
            readyAt: Date()
        )

        let key1 = try factory.derivePublicKey(for: voucher1)
        let key2 = try factory.derivePublicKey(for: voucher2)

        #expect(key1 != key2)
    }

    @Test("Successfully creates a key manager")
    func createKeyManagerSuccess() throws {
        let voucher = Voucher(
            exponent: 0,
            derivationIndex: 5,
            allocatedAt: Date(),
            readyAt: Date()
        )

        let manager: BandersnatchKeyManaging? = try factory.createKeyManager(for: voucher)
        #expect(manager != nil)
    }

    @Test("Base derivation path is correct")
    func derivationPathCorrectness() {
        let voucher = Voucher(
            exponent: 0,
            derivationIndex: 123,
            allocatedAt: Date(),
            readyAt: Date()
        )

        let path = factory.derivationPath(for: voucher)
        #expect(path == "//pps//ring-vrf//123")
    }
}
