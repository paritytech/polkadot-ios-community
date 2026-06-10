import Foundation
import SubstrateSdk
import Testing
import Web3Core
@testable import Products

struct Web3SummitAbiTests {
    @Test func encodeIsCheckedInProducesCorrectSelector() {
        let address = Data(repeating: 0xAB, count: 20)
        let encoded = Web3SummitAbi.encodeIsCheckedIn(address: address)

        // isCheckedIn(address) selector = 0x30cf203a
        #expect(encoded.prefix(4).toHex() == "30cf203a")
    }

    @Test func encodeIsCheckedInLeftPadsAddressTo32Bytes() {
        let address = Data(repeating: 0xAB, count: 20)
        let encoded = Web3SummitAbi.encodeIsCheckedIn(address: address)

        // 4-byte selector + 12 zero bytes + 20-byte address
        #expect(encoded.count == 36)
        #expect(encoded.subdata(in: 4 ..< 16) == Data(repeating: 0, count: 12))
        #expect(encoded.subdata(in: 16 ..< 36) == address)
    }

    @Test func decodeIsCheckedInReturnsTrueForOneWord() {
        let abiTrue = try? #require(abiEncodeBool(true))
        #expect(Web3SummitAbi.decodeIsCheckedIn(output: abiTrue ?? Data()) == true)
    }

    @Test func decodeIsCheckedInReturnsFalseForZeroWord() {
        let abiFalse = try? #require(abiEncodeBool(false))
        #expect(Web3SummitAbi.decodeIsCheckedIn(output: abiFalse ?? Data()) == false)
    }

    @Test func decodeIsCheckedInReturnsNilForEmptyOutput() {
        #expect(Web3SummitAbi.decodeIsCheckedIn(output: Data()) == nil)
    }
}

private func abiEncodeBool(_ value: Bool) -> Data? {
    ABIEncoder.encode(types: [.bool], values: [value])
}
