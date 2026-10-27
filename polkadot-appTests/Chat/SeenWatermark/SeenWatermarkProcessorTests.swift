import Foundation
import Testing

@testable import polkadot_app

struct SeenWatermarkProcessorTests {
    private let fixture = SeenWatermarkStorageFixture()

    @Test func advancesPeerSeenOrderToKnownOutgoingMessageOrder() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 4)

        try await makeProcessor().apply([watermark("sent")], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 4)
    }

    @Test func olderWatermarkKeepsNewerPeerSeenOrder() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "older", order: 4)
        try await insertOutgoing(id: "newer", order: 9)
        let processor = makeProcessor()

        try await processor.apply([watermark("newer")], from: fixture.peerAccountId)
        try await processor.apply([watermark("older")], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 9)
    }

    @Test func unknownMessageIdResolvesToOutgoingOrderAtOrBeforeTimestamp() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "first", order: 1, timestamp: 100)
        try await insertOutgoing(id: "second", order: 2, timestamp: 200)
        try await insertOutgoing(id: "third", order: 3, timestamp: 300)

        try await makeProcessor().apply([watermark("unknown", timestamp: 250)], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 2)
    }

    @Test func unknownIdWithoutOutgoingRowAtOrBeforeTimestampLeavesPeerSeenOrderUnchanged() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 4, timestamp: 1_000)

        try await makeProcessor().apply([watermark("unknown", timestamp: 500)], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 0)
    }

    @Test func timestampFallbackNeverLowersPeerSeenOrder() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "early", order: 1, timestamp: 100)
        try await insertOutgoing(id: "known", order: 3, timestamp: 1_000)
        let processor = makeProcessor()

        try await processor.apply([watermark("known")], from: fixture.peerAccountId)
        try await processor.apply([watermark("unknown", timestamp: 150)], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 3)
    }

    @Test func timestampFallbackIgnoresIncomingRows() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 2, timestamp: 200)
        try await fixture.insertMessage(
            fixture.makeMessage(id: "incoming", status: .incoming(.new), timestamp: 100),
            order: 5
        )

        try await makeProcessor().apply([watermark("unknown", timestamp: 150)], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 0)
    }

    @Test func timestampFallbackSkipsNewAndFailedOutgoingRows() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 1, timestamp: 100)
        try await insertOutgoing(id: "pending", order: 2, timestamp: 200, status: .outgoing(.new))
        try await insertOutgoing(id: "failed", order: 3, timestamp: 210, status: .outgoing(.failed))

        try await makeProcessor().apply([watermark("unknown", timestamp: 250)], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 1)
    }

    @Test func neverCreatesMessageRows() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 4)
        let processor = makeProcessor()

        try await processor.apply([watermark("unknown")], from: fixture.peerAccountId)
        try await processor.apply([watermark("sent")], from: fixture.peerAccountId)

        #expect(try await fixture.messageCount() == 1)
    }

    @Test func blockedContactReceiptIsIgnored() async throws {
        try await fixture.seedChat(isBlocked: true)
        try await insertOutgoing(id: "sent", order: 4)
        let processor = makeProcessor()
        let blockedContact = fixture.makePeer(isBlocked: true)

        let watermarks = processor.receivedWatermarks(from: [receipt("sent")], contact: blockedContact)
        try await processor.apply(watermarks, from: fixture.peerAccountId)

        #expect(watermarks.isEmpty)
        #expect(try await fixture.peerSeenOrder() == 0)
    }

    @Test func acceptedContactReceiptIsExtracted() async throws {
        let watermarks = makeProcessor().receivedWatermarks(from: [receipt("sent")], contact: fixture.makePeer())

        #expect(watermarks.map(\.messageId) == ["sent"])
    }
}

private extension SeenWatermarkProcessorTests {
    func makeProcessor() -> SeenWatermarkProcessor {
        SeenWatermarkProcessor(storageFacade: fixture.facade)
    }

    func insertOutgoing(
        id: Chat.MessageId,
        order: Int64,
        timestamp: Chat.Timestamp = 1_000,
        status: Chat.LocalMessage.Status = .outgoing(.sent)
    ) async throws {
        try await fixture.insertMessage(
            fixture.makeMessage(id: id, status: status, timestamp: timestamp),
            order: order
        )
    }

    func watermark(
        _ messageId: Chat.MessageId,
        timestamp: UInt64 = 1_000
    ) -> ChatRemoteMessageContent.SeenWatermarkContent {
        .init(messageId: messageId, timestamp: timestamp)
    }

    func receipt(_ messageId: Chat.MessageId) -> Chat.RemoteMessage {
        Chat.RemoteMessage.newMessage(with: ChatRemoteMessageContent.seen(watermark(messageId)))
    }
}
