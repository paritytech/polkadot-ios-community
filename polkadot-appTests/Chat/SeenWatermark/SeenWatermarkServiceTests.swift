import Foundation
import StructuredConcurrencyTestSupport
import Testing

@testable import polkadot_app

struct SeenWatermarkServiceTests {
    private let fixture = SeenWatermarkStorageFixture()
    private let sender = SpyDirectMessageSender()
    private let clock = ManualClock()

    @Test func sendsGreatestOrderSeenDisplayableIncomingMessage() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "first", status: .incoming(.seen), order: 1, timestamp: 100)
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 3, timestamp: 50)
        try await insertMessage(id: "middle", status: .incoming(.seen), order: 2, timestamp: 500)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 50)))
        #expect(sender.sent.first?.accountId == fixture.peerAccountId)
    }

    @Test func sendsLowercasedWatermarkMessageId() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "WATERMARK-ID", status: .incoming(.seen), order: 1, timestamp: 10)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "watermark-id", timestamp: 10)))
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
        try await insertMessage(
            id: "contactAdded",
            status: .incoming(.seen),
            order: 7,
            timestamp: 70,
            content: .contactAdded
        )
        try await insertMessage(
            id: "leftChat",
            status: .incoming(.seen),
            order: 8,
            timestamp: 80,
            content: .leftChat
        )
        try await insertMessage(
            id: "multiChatAccepted",
            status: .incoming(.seen),
            order: 9,
            timestamp: 90,
            content: .multiChatAccepted(.init(
                requestId: "request",
                device: .init(
                    statementAccountId: Data(repeating: 0x01, count: 32),
                    encryptionPublicKey: Data(repeating: 0x02, count: 32)
                )
            ))
        )

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 10)))
    }

    @Test func equalOrderFallsBackToLaterTimestamp() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "older", status: .incoming(.seen), order: 2, timestamp: 100)
        try await insertMessage(id: "newer", status: .incoming(.seen), order: 2, timestamp: 200)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "newer", timestamp: 200)))
    }

    @Test func ignoresUnseenAndOutgoingMessages() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)
        try await insertMessage(id: "unseen", status: .incoming(.new), order: 5, timestamp: 90)
        try await insertMessage(id: "outgoing", status: .outgoing(.sent), order: 9, timestamp: 95)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "watermark", timestamp: 10)))
    }

    @Test func extensionChatSendsNothing() async throws {
        await runScheduledWatermark(makeService().scheduleWatermark(for: .chatExtension("extension", roomId: nil)))

        #expect(sender.sent.isEmpty)
    }

    @Test func chatWithoutCandidateSendsNothing() async throws {
        try await fixture.seedChat()

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sender.sent.isEmpty)
    }

    @Test func pendingChatRequestSendsNothing() async throws {
        let request = Chat.Request(
            requestId: "request",
            contactAccountId: fixture.peerAccountId,
            timestamp: 1,
            status: .outgoing,
            message: nil
        )
        try await fixture.seedChat(pendingRequest: request)
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(try await fixture.hasPendingRequest())
        #expect(sender.sent.isEmpty)
    }

    @Test func blockedContactSendsNothing() async throws {
        try await fixture.seedChat(isBlocked: true)
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sender.sent.isEmpty)
    }

    @Test func watermarkEqualToLastSentMarkDoesNotSend() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 2, timestamp: 20)
        try await fixture.seedLastSentSeen(order: 2, timestamp: 20)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sender.sent.isEmpty)
    }

    @Test func sameOrderNewerTimestampSends() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "newer", status: .incoming(.seen), order: 2, timestamp: 200)
        try await fixture.seedLastSentSeen(order: 2, timestamp: 100)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "newer", timestamp: 200)))
    }

    @Test func higherOrderSendsEvenWithOlderTimestamp() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "higher", status: .incoming(.seen), order: 3, timestamp: 50)
        try await fixture.seedLastSentSeen(order: 2, timestamp: 100)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sentContent() == .seen(.init(messageId: "higher", timestamp: 50)))
    }

    @Test func burstOfTriggersSendsOnceWithNewestWatermark() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "older", status: .incoming(.seen), order: 1, timestamp: 100)
        try await insertMessage(id: "newest", status: .incoming(.seen), order: 2, timestamp: 200)

        let service = makeService()
        let tasks = (0 ..< 3).map { _ in service.scheduleWatermark(for: fixture.chatId) }

        await clock.resumeSleep(for: Self.debounceDelay)
        for task in tasks {
            await task.value
        }

        #expect(sender.sent.count == 1)
        #expect(sentContent() == .seen(.init(messageId: "newest", timestamp: 200)))
    }

    @Test func sendingDoesNotPersistLastSentMark() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)

        await runScheduledWatermark(makeService().scheduleWatermark(for: fixture.chatId))

        #expect(sender.sent.count == 1)
        let lastSentMark = try await fixture.lastSentSeenMark()
        #expect(lastSentMark == (0, 0))
    }

    @Test func repeatedTriggerResendsWhileMarkIsNotAdvancedByDelivery() async throws {
        try await fixture.seedChat()
        try await insertMessage(id: "watermark", status: .incoming(.seen), order: 1, timestamp: 10)
        let service = makeService()

        await runScheduledWatermark(service.scheduleWatermark(for: fixture.chatId))
        await runScheduledWatermark(service.scheduleWatermark(for: fixture.chatId))

        #expect(sender.sent.count == 2)
    }
}

private extension SeenWatermarkServiceTests {
    static let debounceDelay: Duration = .seconds(1)

    func makeService() -> SeenWatermarkService {
        SeenWatermarkService(storageFacade: fixture.facade, sender: sender, clock: clock)
    }

    func runScheduledWatermark(_ task: Task<Void, Never>) async {
        await clock.resumeSleep(for: Self.debounceDelay)
        await task.value
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
