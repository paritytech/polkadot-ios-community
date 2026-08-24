import Testing
import Foundation
@testable import Coinage

// This test suite verifies the byte-level layout of RecyclerCollectionIdentifier.
// The layout MUST exactly mirror Pallet::recycler_collection_identifier
// in pallets/coinage/src/lib.rs. Any changes to byte offsets or encoding
// must be coordinated with the Rust pallet and this test suite.
struct RecyclerCollectionIdentifierTests {
    @Test("Instance zero puts denomination at byte twenty")
    func instanceZeroPutsDenominationAtByteTwenty() {
        let identifier = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(0),
            for: 3
        )

        // Expected: "coinage/recycler" (16 bytes) + 0x00 0x00 0x00 0x00 (instanceId)
        // + 0x03 (denomination) + 11 zero bytes = 32 bytes total
        let expected = Data([
            // "coinage/recycler"
            0x63, 0x6F, 0x69, 0x6E, 0x61, 0x67, 0x65, 0x2F,
            0x72, 0x65, 0x63, 0x79, 0x63, 0x6C, 0x65, 0x72,
            // instanceId 0 in little-endian
            0x00, 0x00, 0x00, 0x00,
            // denomination 3
            0x03,
            // 11 zero bytes padding
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        #expect(identifier == expected)
    }

    @Test("Instance ID is encoded in little-endian")
    func instanceIdIsLittleEndian() {
        let identifier = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(258), // 0x0000_0102
            for: 7
        )

        // bytes 16..20 should be 0x02 0x01 0x00 0x00 in little-endian
        #expect(identifier[16] == 0x02)
        #expect(identifier[17] == 0x01)
        #expect(identifier[18] == 0x00)
        #expect(identifier[19] == 0x00)

        // byte 20 should be the denomination
        #expect(identifier[20] == 7)
    }

    @Test("Length is always thirty-two bytes")
    func lengthIsAlwaysThirtyTwo() {
        let id1 = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(0),
            for: 0
        )
        #expect(id1.count == 32)

        let id2 = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(65_535),
            for: 15
        )
        #expect(id2.count == 32)

        let id3 = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(1_000_000),
            for: 31
        )
        #expect(id3.count == 32)
    }

    @Test("Different instances produce different identifiers")
    func differentInstancesProduceDifferentIdentifiers() {
        let id0 = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(0),
            for: 5
        )
        let id1 = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(1),
            for: 5
        )

        #expect(id0 != id1)
    }

    @Test("Denomination occupies byte twenty, not byte sixteen")
    func denominationOccupiesByteTwentyNotSixteen() {
        let identifier = RecyclerCollectionIdentifier.identifier(
            instanceId: CoinageInstanceId(0),
            for: 42
        )

        // byte 16 should be zero (start of instanceId)
        #expect(identifier[16] == 0x00)

        // byte 20 should be the denomination, not byte 16
        #expect(identifier[20] == 42)
    }
}
