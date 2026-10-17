import Foundation
import StatementStore
import SubstrateSdk
import Testing
@testable import MessageExchangeKit

/// Fixed vectors shared with Android; the expected bytes were computed independently of this implementation.
struct StatementWireVectorsTests {
    let ackRequestId = "00000000-0000-0000-0000-000000000001"
    let pendingRequestId = "00000000-0000-0000-0000-000000000002"

    @Test func stateChannel() throws {
        let sessionId = MessageExchange.SessionId(
            own: Data(repeating: 1, count: 32),
            peer: Data(repeating: 2, count: 32),
            ownParameter: Data(),
            peerParameter: Data(),
            channelKey: Data(repeating: 7, count: 32)
        )

        let channel = try ChatStatementChannelFactory().createStateChannel(for: sessionId).fixedStatementFieldData()

        #expect(channel.toHex() == "da9232a4d746228d9a1beca3539d39b3fb1ae138baeded4f03d6f19d695b96d1")
    }

    @Test(arguments: [
        (hasAck: false, hasRequest: false, hex: "040000"),
        (
            hasAck: true,
            hasRequest: false,
            hex: "04019030303030303030302d303030302d303030302d303030302d3030303030303030303030310000"
        ),
        (
            hasAck: false,
            hasRequest: true,
            hex: "0400019030303030303030302d303030302d303030302d303030302d30303030303030303030303200"
        ),
        (
            hasAck: true,
            hasRequest: true,
            hex: "04019030303030303030302d303030302d303030302d303030302d30303030303030303030303100"
                + "019030303030303030302d303030302d303030302d303030302d30303030303030303030303200"
        )
    ])
    func stateEncoding(hasAck: Bool, hasRequest: Bool, hex: String) throws {
        let state = MessageExchange.SessionState<TestMessage>(
            response: hasAck ? .init(requestId: ackRequestId, responseCode: .success) : nil,
            request: hasRequest ? .init(requestId: pendingRequestId, messages: []) : nil
        )

        let encoded = try StatementData<TestMessage>.state(state).scaleEncoded()

        #expect(encoded.toHex() == hex)
        #expect(try StatementData<TestMessage>(scaleDecoder: ScaleDecoder(data: encoded)) == .state(state))
    }

    @Test(arguments: [(41, 1_024), (1_024, 1_024), (1_025, 2_048), (300 * 1_024, 500 * 1_024 - 28 - 4)])
    func paddedPlaintextLength(plaintextSize: Int, paddedSize: Int) {
        let padding = StatementPayloadPadding(maxPayloadSize: 500 * 1_024)

        #expect(padding.pad(Data(count: plaintextSize)).count == paddedSize)
    }
}
