import CryptoKit
import Foundation
import Testing
@testable import MessageExchangeKit

struct OutgoingRequestStateSizingTests {
    @Test func messageThatFitsOnlyWithoutTheAckIsRejected() throws {
        let coder = try makeUnpaddedCoder()
        let message = TestMessage(id: 1)
        let requestOnly = try coder.encodeToScaleEncodedPayload(
            StatementData<TestMessage>.state(.init(
                response: nil,
                request: .init(requestId: UUID().uuidString, messages: [message])
            )),
            route: .device
        )
        let withAck = try coder.encodeForSizing(requestId: UUID().uuidString, messages: [message], route: .device)
        let queue = OutgoingRequestQueue<TestMessage>(
            statementDataCoder: coder,
            routeSelector: PeerSessionRouteSelector { $0.route },
            sizeValidator: StaticSizeValidator(maxPayloadSize: withAck.count - 1),
            supportedRoutes: [.device],
            logger: nil
        )

        let results = queue.addMessages([message], isChannelActive: true)

        #expect(requestOnly.count < withAck.count - 1)
        guard case .failure(.messageTooBig) = results.first else {
            Issue.record("Expected messageTooBig, got \(results)")
            return
        }
    }
}

private extension OutgoingRequestStateSizingTests {
    func makeUnpaddedCoder() throws -> StatementDataCoder {
        let encryptor = try X25519ChaChaPolyEncryptorFactory(privateKey: Curve25519.KeyAgreement.PrivateKey())
            .makeEncryptor(remotePublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        return StatementDataCoder(
            encryptor: encryptor,
            padding: StatementPayloadPadding(maxPayloadSize: 0),
            logger: nil
        )
    }
}

private final class StaticSizeValidator: OutgoingRequestSizeValidating {
    let maxPayloadSize: Int

    init(maxPayloadSize: Int) {
        self.maxPayloadSize = maxPayloadSize
    }
}
