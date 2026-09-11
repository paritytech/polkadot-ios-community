import Foundation
import Testing
import SubstrateSdk
@testable import Products

@Suite("PaymentRequestDto Tests")
struct PaymentRequestDtoTests {
    private let idHex = "0x" + String(repeating: "ab", count: 32)
    private let destinationHex = "0x" + String(repeating: "cd", count: 32)

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("decodes the wire shape with 32-byte id and destination")
    func decodesWireShape() throws {
        let json = #"{"id":"\#(idHex)","amount":"1500","destinationHex":"\#(destinationHex)"}"#

        let dto = try decode(PaymentRequestDto.self, json: json)

        #expect(dto.id == Data(repeating: 0xAB, count: 32))
        #expect(dto.amount == 1_500)
        #expect(dto.destination == Data(repeating: 0xCD, count: 32))
        #expect(dto.id.toHex(includePrefix: true) == idHex)
    }

    @Test("rejects an id that is not 32 bytes", arguments: [31, 33])
    func rejectsWrongIdLength(byteCount: Int) {
        let shortId = "0x" + String(repeating: "ab", count: byteCount)
        let json = #"{"id":"\#(shortId)","amount":"1","destinationHex":"\#(destinationHex)"}"#

        #expect(throws: DecodingError.self) {
            try decode(PaymentRequestDto.self, json: json)
        }
    }

    @Test("status subscribe decodes paymentId with the same rule")
    func statusSubscribeDecodes() throws {
        let dto = try decode(PaymentStatusSubscribeDto.self, json: #"{"paymentId":"\#(idHex)"}"#)
        #expect(dto.paymentId == Data(repeating: 0xAB, count: 32))

        #expect(throws: DecodingError.self) {
            try decode(PaymentStatusSubscribeDto.self, json: #"{"paymentId":"0xab"}"#)
        }
    }

    @Test("status dto keeps the legacy tagged shape")
    func statusDtoShape() throws {
        let failed = try HostPaymentStatusDto(status: .failed(reason: "boom")).toScaleCompatibleJSON()
        #expect(failed.tag?.stringValue == "Failed")
        #expect(failed.value?.stringValue == "boom")

        let processing = try HostPaymentStatusDto(status: .processing).toScaleCompatibleJSON()
        #expect(processing.tag?.stringValue == "Processing")
        #expect(processing.value == nil)

        let completed = try HostPaymentStatusDto(status: .completed).toScaleCompatibleJSON()
        #expect(completed.tag?.stringValue == "Completed")
        #expect(completed.value == nil)

        let partial = try HostPaymentStatusDto(status: .partiallyClaimed(settledInPlanks: 1_500))
            .toScaleCompatibleJSON()
        #expect(partial.tag?.stringValue == "PartiallyClaimed")
        #expect(partial.value?.stringValue == "1500")
    }
}
