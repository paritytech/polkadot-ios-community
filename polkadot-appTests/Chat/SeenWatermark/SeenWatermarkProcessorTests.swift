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

    @Test func unknownMessageIdLeavesPeerSeenOrderUnchanged() async throws {
        try await fixture.seedChat()
        try await insertOutgoing(id: "sent", order: 4)

        try await makeProcessor().apply([watermark("unknown")], from: fixture.peerAccountId)

        #expect(try await fixture.peerSeenOrder() == 0)
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

    func insertOutgoing(id: Chat.MessageId, order: Int64) async throws {
        try await fixture.insertMessage(
            fixture.makeMessage(id: id, status: .outgoing(.sent), timestamp: 1_000),
            order: order
        )
    }

    func watermark(_ messageId: Chat.MessageId) -> ChatRemoteMessageContent.SeenWatermarkContent {
        .init(messageId: messageId, timestamp: 1_000)
    }

    func receipt(_ messageId: Chat.MessageId) -> Chat.RemoteMessage {
        Chat.RemoteMessage.newMessage(with: ChatRemoteMessageContent.seen(watermark(messageId)))
    }
}
