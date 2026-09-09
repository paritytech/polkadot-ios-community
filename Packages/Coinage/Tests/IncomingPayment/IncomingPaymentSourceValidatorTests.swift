import Testing
import Foundation
import NovaCrypto
@testable import Coinage

struct IncomingPaymentSourceValidatorTests {
    private let validator = IncomingPaymentSourceValidator()
    private let keyFactory = SNKeyFactory()

    /// A valid 64-byte sr25519 secret key derived from a 32-byte seed.
    private func validSecret(_ seedByte: UInt8) throws -> Data {
        let seed = Data(repeating: seedByte, count: 32)
        return try keyFactory.createKeypair(fromSeed: seed).privateKey().rawData()
    }

    @Test func fingerprintsOneKeyPerCoin() throws {
        let keys = try [validSecret(0x01), validSecret(0x02)]
        let fingerprints = try validator.fingerprints(for: .coinsFromPrivateKeys(secretKeys: keys))
        #expect(fingerprints.count == 2)
    }

    @Test func fingerprintForExternalAssetWallet() throws {
        let fingerprints = try validator.fingerprints(for: .externalAssetFromWallet(secretKey: validSecret(0x03)))
        #expect(fingerprints.count == 1)
    }

    @Test func sameKeyProducesSameFingerprint() throws {
        let key = try validSecret(0x04)
        let first = try validator.fingerprints(for: .coinsFromPrivateKeys(secretKeys: [key]))
        let second = try validator.fingerprints(for: .externalAssetFromWallet(secretKey: key))
        #expect(first == second)
    }

    @Test func emptyCoinsSourceIsInvalid() {
        #expect {
            _ = try validator.fingerprints(for: .coinsFromPrivateKeys(secretKeys: []))
        } throws: { Self.isInvalidSource($0) }
    }

    @Test func malformedKeyIsInvalid() {
        // A seed-sized (32-byte) blob is not a valid 64-byte secret key.
        let malformed = Data(repeating: 0, count: 32)
        #expect {
            _ = try validator.fingerprints(for: .externalAssetFromWallet(secretKey: malformed))
        } throws: { Self.isInvalidSource($0) }
    }

    private static func isInvalidSource(_ error: any Error) -> Bool {
        guard let error = error as? IncomingPaymentError, case .invalidSource = error else {
            return false
        }
        return true
    }
}
