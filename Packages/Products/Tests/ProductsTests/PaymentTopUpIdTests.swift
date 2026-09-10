import Foundation
import SubstrateSdk
import Testing
@testable import Products

struct PaymentTopUpIdTests {
    private let validBytes = Data(repeating: 0xAB, count: PaymentTopUpId.sizeBytes)

    @Test func acceptsExactly32Bytes() throws {
        let id = try PaymentTopUpId.fromBytes(validBytes)
        #expect(id.bytes == validBytes)
    }

    @Test(arguments: [0, 1, 31, 33, 64])
    func rejectsWrongLength(count: Int) {
        #expect(throws: PaymentTopUpIdError.invalidLength(count)) {
            try PaymentTopUpId.fromBytes(Data(repeating: 0x01, count: count))
        }
    }

    @Test func hexRoundTrips() throws {
        let id = try PaymentTopUpId.fromBytes(validBytes)
        let restored = try PaymentTopUpId.fromHex(id.asHex())
        #expect(restored == id)
    }

    @Test func fromHexAcceptsPrefixedAndBare() throws {
        let bare = validBytes.toHex()
        let prefixed = validBytes.toHex(includePrefix: true)
        #expect(try PaymentTopUpId.fromHex(bare) == PaymentTopUpId.fromHex(prefixed))
    }

    @Test func decodesFromHexString() throws {
        let json = try JSONSerialization.data(withJSONObject: [validBytes.toHex(includePrefix: true)])
        let decoded = try JSONDecoder().decode([PaymentTopUpId].self, from: json)
        #expect(decoded.first?.bytes == validBytes)
    }

    @Test func decodingRejectsWrongLength() throws {
        let json = try JSONSerialization.data(withJSONObject: [Data([0x01]).toHex()])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([PaymentTopUpId].self, from: json)
        }
    }

    @Test func equalIdsShareHash() throws {
        let a = try PaymentTopUpId.fromBytes(validBytes)
        let b = try PaymentTopUpId.fromHex(validBytes.toHex())
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
