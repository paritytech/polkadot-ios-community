@testable import polkadot_app
import Foundation
import MessageExchangeKit
import NovaCrypto
import StatementStore
import SubstrateSdk
import SubstrateSdkExt
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferTransportTests {
    private static let requestId = "6f1c2a9e-3b4d-4e5f-8a7b-0c1d2e3f4a5b"
    private static let otherRequestId = "0b2d6c1e-7a4f-4c3b-9e8d-1f2a3b4c5d6e"

    private let store = MockStatementStore()
    private let schedule: DeviceTransferKeySchedule
    private let identityKeypair: SNKeypairProtocol

    init() throws {
        schedule = try DeviceTransferKeySchedule(entropy: Data(repeating: 0x01, count: 16))
        identityKeypair = try SNKeyFactory().createKeypair(fromSeed: Data.randomOrError(of: 32))
    }

    @Test("Sender and receiver exchange signaling envelopes in both directions")
    func signalingBothWays() async throws {
        let sender = try await openPeer(role: .sender)
        let receiver = try await openPeer(role: .receiver)
        let offer = Chat.DeviceSyncSignalingEnvelope(offerId: "offer-1", message: .offer(Data([1, 2])))
        let answer = Chat.DeviceSyncSignalingEnvelope(offerId: "offer-1", message: .answer(Data([3])))

        try await sender.transport.send([offer.scaleEncoded()])
        #expect(await firstBatch(of: receiver) == [offer])

        try await receiver.transport.send([answer.scaleEncoded()])
        #expect(await firstBatch(of: sender) == [answer])

        await close(sender, receiver)
    }

    @Test("A rejection reaches the receiver's rejection stream, not its signaling")
    func rejectionReachesReceiver() async throws {
        let sender = try await openPeer(role: .sender)
        let receiver = try await openPeer(role: .receiver)

        await sender.transport.sendRejection()

        var iterator = receiver.transport.rejections.makeAsyncIterator()
        #expect(await iterator.next() != nil)

        await close(sender, receiver)
    }

    @Test("Transfer statements expire after the statement lifetime")
    func statementsAreShortLived() async throws {
        let sender = try await openPeer(role: .sender)
        let receiver = try await openPeer(role: .receiver)
        let envelope = Chat.DeviceSyncSignalingEnvelope(offerId: "offer-1", message: .reconnected)
        let expectedExpiry = UInt64(Date().timeIntervalSince1970 + DeviceTransferConstants.statementLifetimeInSeconds)

        try await sender.transport.send([envelope.scaleEncoded()])
        _ = await firstBatch(of: receiver)

        let expiries = try store.getStatements(with: .anyTopic).map { try Statement.fromScaleEncoded($0).getExpiry() }
        #expect(!expiries.isEmpty)
        for expiry in expiries {
            let expiresAt = try #require(expiry) >> 32
            #expect((expectedExpiry - 5 ... expectedExpiry + 5).contains(expiresAt))
        }

        await close(sender, receiver)
    }

    @Test("A receiver for another request doesn't get this request's messages")
    func otherRequestIsIsolated() async throws {
        let sender = try await openPeer(role: .sender)
        let otherSender = try await openPeer(role: .sender, requestId: Self.otherRequestId)
        let otherReceiver = try await openPeer(role: .receiver, requestId: Self.otherRequestId)
        let ownOffer = Chat.DeviceSyncSignalingEnvelope(offerId: "own", message: .reconnected)
        let otherOffer = Chat.DeviceSyncSignalingEnvelope(offerId: "other", message: .reconnected)

        try await sender.transport.send([ownOffer.scaleEncoded()])
        try await otherSender.transport.send([otherOffer.scaleEncoded()])

        #expect(await firstBatch(of: otherReceiver) == [otherOffer])

        await close(sender, otherSender, otherReceiver)
    }
}

private struct TransferPeer {
    let transport: DeviceTransferTransport
    let delegate: DeviceSyncPeerSessionDelegate
}

private extension DeviceTransferTransportTests {
    func openPeer(role: DeviceTransferRole, requestId: String = Self.requestId) async throws -> TransferPeer {
        let signer = StatementStoreKeypairSigner(keypair: identityKeypair)
        let transport = try DeviceTransferTransport(
            context: DeviceTransferSessionContext(
                connection: store,
                signerManager: ClosureSignerManager { _ in signer },
                ownSignKeyId: "identity",
                keySchedule: schedule,
                requestId: requestId,
                role: role
            ),
            logger: MockLogger()
        )
        let delegate = transport.makeSessionDelegate()
        try await transport.open(delegate: AnyPeerSessionDelegate(delegate))

        return TransferPeer(transport: transport, delegate: delegate)
    }

    func close(_ peers: TransferPeer...) async {
        for peer in peers {
            await peer.transport.close()
        }
    }

    func firstBatch(of peer: TransferPeer) async -> [Chat.DeviceSyncSignalingEnvelope]? {
        for await batch in peer.delegate.incomingEnvelopes {
            return batch
        }
        return nil
    }
}
