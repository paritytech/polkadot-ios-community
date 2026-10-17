import CryptoKit
import Foundation
import SubstrateSdk
import Testing
@testable import MessageExchangeKit

struct SessionStateCodingTests {
    let alice = Curve25519.KeyAgreement.PrivateKey()
    let bob = Curve25519.KeyAgreement.PrivateKey()

    @Test(arguments: [
        (hasResponse: false, hasRequest: false),
        (hasResponse: true, hasRequest: false),
        (hasResponse: false, hasRequest: true),
        (hasResponse: true, hasRequest: true)
    ])
    func stateRoundTrips(hasResponse: Bool, hasRequest: Bool) throws {
        let state = MessageExchange.SessionState<TestMessage>(
            response: hasResponse ? ack("peer-request") : nil,
            request: hasRequest ? .init(requestId: "own-request", messages: [TestMessage(id: 7)]) : nil
        )

        let decoded = try roundTrip(.state(state))

        #expect(decoded == .state(state))
    }

    @Test func ackOnlyAndShortMessageStatesHaveEqualPayloadLength() throws {
        let ackOnly = try makeCoder().encodeToScaleEncodedPayload(
            StatementData<TestMessage>.state(.init(response: ack("peer-request"), request: nil)),
            route: .identity
        )
        let withMessage = try makeCoder().encodeToScaleEncodedPayload(
            StatementData<TestMessage>.state(.init(
                response: nil,
                request: .init(requestId: UUID().uuidString, messages: [TestMessage(id: 1), TestMessage(id: 2)])
            )),
            route: .identity
        )

        #expect(ackOnly.count == withMessage.count)
    }

    @Test func unpaddedPayloadStillDecodes() throws {
        let state = MessageExchange.SessionState<TestMessage>(response: ack("peer-request"), request: nil)
        let unpadded = try makeCoder(padding: StatementPayloadPadding(maxPayloadSize: 0))
            .encodeToScaleEncodedPayload(StatementData<TestMessage>.state(state), route: .identity)

        let result: StatementDataDecodingResult<TestMessage> = try makeCoder(keys: (bob, alice))
            .decodeFromScaleEncodedPayload(unpadded, senderAccountId: nil, route: .identity)

        #expect(result.statementData == .state(state))
    }

    @Test func undecodableMessagesKeepResponseAndRequestId() throws {
        let state = MessageExchange.SessionState<RejectedMessage>(
            response: ack("peer-request"),
            request: .init(requestId: "own-request", messages: [RejectedMessage()])
        )
        let payload = try makeCoder().encodeToScaleEncodedPayload(
            StatementData<RejectedMessage>.state(state),
            route: .identity
        )

        let result: StatementDataDecodingResult<RejectedMessage> = try makeCoder(keys: (bob, alice))
            .decodeFromScaleEncodedPayload(payload, senderAccountId: nil, route: .identity)

        guard case let .partial(response, requestId, _) = result else {
            Issue.record("Expected a partial result, got \(result)")
            return
        }
        #expect(response == ack("peer-request"))
        #expect(requestId == "own-request")
    }

    @Test func multiDeviceStateRoundTrips() throws {
        let recipientDevice = Curve25519.KeyAgreement.PrivateKey()
        let recipientAccountId = Data(repeating: 9, count: 32)
        let state = MessageExchange.SessionState<TestMessage>(
            response: ack("peer-request"),
            request: .init(requestId: "own-request", messages: [TestMessage(id: 3)])
        )

        let envelope = try MultiDeviceStatementDataCoder(
            deviceEncryptionKeyFactory: X25519ChaChaPolyEncryptorFactory(privateKey: alice),
            logger: nil
        ).encodeMultiDeviceState(
            state,
            recipients: [.init(
                statementAccountId: recipientAccountId,
                encryptionPublicKey: recipientDevice.publicKey.rawRepresentation
            )]
        )

        let decoded: StatementDataDecodingResult<TestMessage> = try MultiDeviceStatementDataCoder(
            deviceEncryptionKeyFactory: X25519ChaChaPolyEncryptorFactory(privateKey: recipientDevice),
            logger: nil
        ).decodeMultiDeviceState(
            envelope,
            ownStatementAccountId: recipientAccountId,
            peerDevicePublicKey: alice.publicKey.rawRepresentation
        )

        #expect(decoded.statementData == .state(state))
        #expect(envelope.devicesInfo.map(\.statementAccountId) == [recipientAccountId])
    }

    @Test(arguments: [UInt8(0), 1, 2, 3, 9])
    func retiredOrUnknownVariantFailsDecoding(index: UInt8) throws {
        let encryptor = try X25519ChaChaPolyEncryptorFactory(privateKey: alice)
            .makeEncryptor(remotePublicKey: bob.publicKey.rawRepresentation)
        let payload = try encryptor.encrypt(Data([index, 0, 0])).scaleEncoded()

        #expect(throws: StatementDataDecodingError.self) {
            let _: StatementDataDecodingResult<TestMessage> = try makeCoder(keys: (bob, alice))
                .decodeFromScaleEncodedPayload(payload, senderAccountId: nil, route: .identity)
        }
    }
}

private extension SessionStateCodingTests {
    func ack(_ requestId: String) -> MessageExchange.Response {
        MessageExchange.Response(requestId: requestId, responseCode: .success)
    }

    func makeCoder(
        keys: (own: Curve25519.KeyAgreement.PrivateKey, peer: Curve25519.KeyAgreement.PrivateKey)? = nil,
        padding: StatementPayloadPadding = StatementPayloadPadding(maxPayloadSize: 500 * 1_024)
    ) throws -> StatementDataCoder {
        let (own, peer) = keys ?? (alice, bob)
        let encryptor = try X25519ChaChaPolyEncryptorFactory(privateKey: own)
            .makeEncryptor(remotePublicKey: peer.publicKey.rawRepresentation)
        return StatementDataCoder(encryptor: encryptor, padding: padding, logger: nil)
    }

    func roundTrip(_ data: StatementData<TestMessage>) throws -> StatementData<TestMessage>? {
        let payload = try makeCoder().encodeToScaleEncodedPayload(data, route: .identity)
        let result: StatementDataDecodingResult<TestMessage> = try makeCoder(keys: (bob, alice))
            .decodeFromScaleEncodedPayload(payload, senderAccountId: nil, route: .identity)
        return result.statementData
    }
}

private extension StatementDataDecodingResult {
    var statementData: StatementData<M>? {
        if case let .statementData(data) = self { data } else { nil }
    }
}

/// Encodes fine but always fails to decode, like a message from a newer app version.
private struct RejectedMessage: MessageExchange.CodableMessage {
    init() {}

    init(scaleDecoder _: any ScaleDecoding) throws {
        throw ScaleCodingError.unexpectedDecodedValue
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try UInt8(0xFF).encode(scaleEncoder: scaleEncoder)
    }
}
