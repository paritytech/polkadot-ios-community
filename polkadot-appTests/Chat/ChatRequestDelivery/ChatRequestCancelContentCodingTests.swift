@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

struct ChatRequestCancelContentCodingTests {
    @Test("A cancel request message round-trips through SCALE")
    func cancelMessageRoundtrip() throws {
        let message = Chat.RequestMessage(
            messageId: "r1",
            timestamp: 42,
            content: .cancel(makeCancelContent())
        )

        let decoded = try Chat.RequestMessage(
            scaleDecoder: ScaleDecoder(data: message.scaleEncoded())
        )

        #expect(decoded == message)
    }

    @Test("A cancel content is encoded with version index 2")
    func cancelContentVersionIndex() throws {
        let encoded = try Chat.VersionedRequestContent.cancel(makeCancelContent()).scaleEncoded()

        #expect(encoded.first == 2)
    }

    @Test("An unknown content version index is rejected")
    func unknownVersionIndexIsRejected() throws {
        let data = Data([3]) + Data(repeating: 0, count: 64)

        #expect(throws: ScaleCodingError.self) {
            try Chat.VersionedRequestContent(scaleDecoder: ScaleDecoder(data: data))
        }
    }
}

private extension ChatRequestCancelContentCodingTests {
    func makeCancelContent() -> Chat.RequestContentCancel {
        Chat.RequestContentCancel(
            identityProof: Chat.IdentityProof(
                identityAccountId: Data(repeating: 0x07, count: 32),
                proof: Data(repeating: 0x09, count: 32)
            )
        )
    }
}
