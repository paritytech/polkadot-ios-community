@testable import polkadot_app
import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdkExt
import Testing

/// Session vectors from the Device Transfer RFC, built through the same factories a peer session uses.
struct DeviceTransferSessionVectorTests {
    private static let requestId = "6f1c2a9e-3b4d-4e5f-8a7b-0c1d2e3f4a5b"

    @Test("Session ids and request channels match the RFC vectors in both directions")
    func sessionVectors() throws {
        let schedule = try DeviceTransferKeySchedule(entropy: "0x000102030405060708090a0b0c0d0e0f".fromHex())
        let receiverSessionId = try makeSessionId(
            schedule: schedule,
            own: schedule.receiverLabel,
            peer: schedule.senderLabel
        )
        let channels = ChatStatementChannelFactory()

        let expected = (
            receiverToSender: "c0c5c7eb24816b3c79506ad83012360860cf0ecce4274a8b9e58f1b80824c84f",
            senderToReceiver: "b080338b43474752b88e95fc32f7f5b6b866d9d1276b8ee1573459877e9c20a5",
            receiverRequest: "d0764d141a5e047eb9b063d59f3abe9188b6955784b6938e86cc733563564450",
            senderRequest: "82c82417fccd9e0d23327a524046d5fd7388f228acd82277b7a9b9b4ff133ee4"
        )

        #expect(receiverSessionId.own.toHex() == expected.receiverToSender)
        #expect(receiverSessionId.peer.toHex() == expected.senderToReceiver)
        #expect(try channels.createRequestChannel(for: receiverSessionId).fixedStatementFieldData().toHex()
            == expected.receiverRequest)
        #expect(try channels.createPeerRequestChannel(for: receiverSessionId).fixedStatementFieldData().toHex()
            == expected.senderRequest)
    }
}

private extension DeviceTransferSessionVectorTests {
    func makeSessionId(
        schedule: DeviceTransferKeySchedule,
        own: Data,
        peer: Data
    ) throws -> MessageExchange.SessionId {
        let encryptor = try PresharedKeyEncryptionManager(presharedKey: schedule.sessionKey(requestId: Self.requestId))
            .makeEncryptorFactory(ownEncryptionKeyId: "")
            .makeEncryptor(remotePublicKey: Data())
        let ownAccountId = try FixedSessionAccountProvider(accountId: own)
            .ownAccountId(for: MessageExchange.Own(signKeyId: "", encryptionKeyId: "", pin: nil))

        return try PeerSessionIdFactory().createSessionId(
            for: PeerSessionInit(
                ownAccountId: ownAccountId,
                ownPin: nil,
                peerAccountId: peer,
                peerPin: nil,
                sharedSecret: encryptor.sharedSecret
            )
        )
    }
}
