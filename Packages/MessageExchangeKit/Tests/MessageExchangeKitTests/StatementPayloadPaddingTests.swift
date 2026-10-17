import Foundation
import Testing
@testable import MessageExchangeKit

struct StatementPayloadPaddingTests {
    let padding = StatementPayloadPadding(maxPayloadSize: 500 * 1_024)

    @Test(arguments: [
        (size: 1, bucket: 1_024),
        (size: 1_023, bucket: 1_024),
        (size: 1_024, bucket: 1_024),
        (size: 1_025, bucket: 2_048),
        (size: 5_000, bucket: 8_192)
    ])
    func padsToPowerOfTwoBucket(size: Int, bucket: Int) {
        #expect(padding.pad(Data(repeating: 1, count: size)).count == bucket)
    }

    @Test func keepsContentAndAppendsZeros() {
        let plaintext = Data([1, 2, 3])

        let padded = padding.pad(plaintext)

        #expect(padded.prefix(3) == plaintext)
        #expect(padded.dropFirst(3).allSatisfy { $0 == 0 })
    }

    @Test func capsAtMaxPlaintextSize() {
        let maxPlaintext = 500 * 1_024 - StatementPayloadPadding.encryptionOverhead - 4

        #expect(padding.pad(Data(count: 300 * 1_024)).count == maxPlaintext)
        #expect(padding.pad(Data(count: maxPlaintext)).count == maxPlaintext)
        #expect(padding.pad(Data(count: maxPlaintext + 1)).count == maxPlaintext + 1)
    }

    @Test func paddedPayloadNeverExceedsLimitWhenUnpaddedFits() throws {
        let maxPayloadSize = 3_000
        let padding = StatementPayloadPadding(maxPayloadSize: maxPayloadSize)
        let paddedPlaintext = padding.pad(Data(count: 2_500))
        let payload = try Data(count: paddedPlaintext.count + StatementPayloadPadding.encryptionOverhead)
            .scaleEncoded()

        #expect(payload.count <= maxPayloadSize)
    }
}
