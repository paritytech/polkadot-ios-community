import Foundation
import Testing

@testable import polkadot_app

struct SeenWatermarkServiceTests {
    private let fixture = SeenWatermarkStorageFixture()
    private let sender = SpyDirectMessageSender()

    @Test func sendsGreatestOrderSeenDisplayableIncomingMessage() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "first", status: .incoming(.seen), order: 1, timestamp: 100)
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 3, timestamp: 50)
        try await insertMessage(id: "middle", status: .incoming(.seen), order: 2, timestamp: 500)

        try await makeService().sendWatermark(for: fixture.chatId)

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 50)))
        #expect(sender.sent.first?.accountId == fixture.peerAccountId)
    }

    @Test func nonDisplayableSeenMessagesDoNotAdvanceWatermark() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)
        try await insertMessage(
            id: "reaction",
            status: .incoming(.seen),
            order: 2,
            timestamp: 20,
            content: .reacted(.init(messageId: "watermark", emoji: "👍"))
        )
        try await insertMessage(
            id: "edit",
            status: .incoming(.seen),
            order: 3,
            timestamp: 30,
            content: .edited(.init(messageId: "watermark", newContent: .init(text: "edited", attachments: nil)))
        )
        try await insertMessage(
            id: "compacted",
            status: .incoming(.seen),
            order: 4,
            timestamp: 40,
            content: .compactedMessages(.init(
                claimIdentifier: Data(repeating: 0x01, count: 32),
                claimTicket: Data(repeating: 0x02, count: 32),
                node: .wssUrl("wss://localhost:8000")
            ))
        )
        try await insertMessage(
            id: "accepted",
            status: .incoming(.seen),
            order: 5,
            timestamp: 50,
            content: .chatAccepted(.init(messageId: "watermark"))
        )
        try await insertMessage(
            id: "device",
            status: .incoming(.seen),
            order: 6,
            timestamp: 60,
            content: .deviceAdded(.init(
                statementAccountId: Data(repeating: 0x01, count: 32),
                encryptionPublicKey: Data(repeating: 0x02, count: 32)
            ))
        )

        try await makeService().sendWatermark(for: fixture.chatId)

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 10)))
    }

    @Test func equalOrderFallsBackToLaterTimestamp() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "older", status: .incoming(.seen), order: 2, timestamp: 100)
        try await insertMessage(id: "newer", status: .incoming(.seen), order: 2, timestamp: 200)

        try await makeService().sendWatermark(for: fixture.chatId)

        #expect(sentContent() == .seen(.init(messageId: "newer", timestamp: 200)))
    }

    @Test func ignoresUnseenAndOutgoingMessages() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)
        try await insertMessage(id: "unseen", status: .incoming(.new), order: 5, timestamp: 90)
        try await insertMessage(id: "outgoing", status: .outgoing(.sent), order: 9, timestamp: 95)

        try await makeService().sendWatermark(for: fixture.chatId)

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 10)))
    }

    @Test func extensionChatSendsNothing() async throws {
        try await makeService().sendWatermark(for: .chatExtension("extension", roomId: nil))

        #expect(sender.sent.isEmpty)
    }

    @Test func chatWithoutCandidateSendsNothing() async throws {
        try await fixture.seedChat()

        try await makeService().sendWatermark(for: fixture.chatId)

        #expect(sender.sent.isEmpty)
    }
}

private extension SeenWatermarkServiceTests {
    func makeService() -> SeenWatermarkService {
        SeenWatermarkService(storageFacade: fixture.facade, sender: sender)
    }

    func insertMessage(
        id: Chat.MessageId,
        status: Chat.LocalMessage.Status,
        order: Int64,
        timestamp: Chat.Timestamp,
        content: Chat.LocalMessage.Content = .text("text")
    ) async throws {
        try await fixture.insertMessage(
            fixture.makeMessage(id: id, status: status, timestamp: timestamp, content: content),
            order: order
        )
    }

    func sentContent() -> Chat.RemoteMessageContentV1.MessageContent? {
        sender.sent.first?.message.versioned.ensureV1()?.content
    }
}
