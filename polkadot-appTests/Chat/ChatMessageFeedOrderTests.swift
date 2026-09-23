import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

@Suite("Chat feed order")
final class ChatMessageFeedOrderTests {
    private let facade = UserDataStorageTestFacade()
    private let counterURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "order-\(UUID().uuidString)"
    )
    private var orderAllocator: FileChatMessageOrderAllocator {
        FileChatMessageOrderAllocator(fileURL: counterURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: counterURL)
    }

    private let alice = Chat.Contact(
        accountId: Data(repeating: 0x01, count: 32),
        username: "Alice",
        publicKey: Data(repeating: 0x02, count: 32),
        pin: nil,
        pushId: nil,
        pushToken: nil,
        voipPushToken: nil,
        peerPlatform: nil,
        lastOwnToken: nil,
        voipLastOwnToken: nil,
        chatRequest: nil,
        ownKeyId: .init(signKeyId: "sign-key", encryptionKeyId: "encryption-key"),
        imageData: nil,
        source: .chat,
        isBlocked: false,
        devices: [],
        pendingDevicesFanOut: false
    )

    @Test("outgoing message sent after a received one appears after it when sender clock runs ahead")
    func outgoingAfterReceivedWithSenderClockAhead() async throws {
        try await seedChat()

        let localNow = Date().toChatTimestamp()
        let senderClockAhead = localNow + 60_000

        try await save(
            makeMessage(
                id: "received",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: senderClockAhead
            )
        )
        try await save(
            makeMessage(id: "sent", origin: .user, status: .outgoing(.new), timestamp: localNow)
        )

        let messages = try await feed(expectedCount: 2)
        #expect(messages == ["received", "sent"])
    }

    @Test("chat preview shows the later-ordered message despite sender clock ahead")
    func chatPreviewWithSenderClockAhead() async throws {
        try await seedChat()

        let localNow = Date().toChatTimestamp()
        let senderClockAhead = localNow + 60_000

        try await save(
            makeMessage(
                id: "received",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: senderClockAhead
            )
        )
        try await save(
            makeMessage(id: "sent", origin: .user, status: .outgoing(.new), timestamp: localNow)
        )

        let lastId = try await lastMessageId()
        #expect(lastId == "sent")
    }

    @Test("synced backlog message sorts by timestamp among legacy history")
    func syncedBacklogInLegacyHistory() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()

        try await save(
            makeMessage(
                id: "legacy-old",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: 1_000,
                creationSource: .localDevice
            ),
            allocator: StubChatMessageOrderAllocator(value: 0)
        )
        try await save(
            makeMessage(
                id: "legacy-new",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: 3_000,
                creationSource: .localDevice
            ),
            allocator: StubChatMessageOrderAllocator(value: 0)
        )
        try await save(
            makeMessage(
                id: "sent-now",
                origin: .user,
                status: .outgoing(.sent),
                timestamp: now
            )
        )
        try await save(
            makeMessage(
                id: "synced-backlog",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: 2_000,
                creationSource: .deviceSync
            )
        )

        let messages = try await feed(expectedCount: 4)
        #expect(messages == ["legacy-old", "synced-backlog", "legacy-new", "sent-now"])

        let lastId = try await lastMessageId()
        #expect(lastId == "sent-now")
    }

    @Test("live synced message lands at the bottom")
    func liveSyncedMessage() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()

        try await save(
            makeMessage(
                id: "received",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: now
            )
        )
        try await save(
            makeMessage(
                id: "synced-live",
                origin: .user,
                status: .outgoing(.sent),
                timestamp: now + 1_000,
                creationSource: .deviceSync
            )
        )

        let messages = try await feed(expectedCount: 2)
        #expect(messages == ["received", "synced-live"])
    }

    @Test("synced backlog message interleaves allocated history by timestamp")
    func syncedBacklogInterleavesAllocatedHistory() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()

        try await save(
            makeMessage(id: "older", origin: .contact(alice.accountId), status: .incoming(.new), timestamp: now)
        )
        try await save(
            makeMessage(id: "newer", origin: .user, status: .outgoing(.sent), timestamp: now + 2_000)
        )
        try await save(
            makeMessage(
                id: "synced-between",
                origin: .user,
                status: .outgoing(.sent),
                timestamp: now + 1_000,
                creationSource: .deviceSync
            )
        )

        let messages = try await feed(expectedCount: 3)
        #expect(messages == ["older", "synced-between", "newer"])

        let lastId = try await lastMessageId()
        #expect(lastId == "newer")
    }

    @Test("a reset counter file keeps new messages after history")
    func resetCounterKeepsNewMessagesLast() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()
        let resetURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "order-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: resetURL) }

        try await save(
            makeMessage(id: "first", origin: .user, status: .outgoing(.sent), timestamp: now + 60_000)
        )
        try await save(
            makeMessage(id: "second", origin: .contact(alice.accountId), status: .incoming(.new), timestamp: now),
            allocator: FileChatMessageOrderAllocator(fileURL: resetURL)
        )

        let messages = try await feed(expectedCount: 2)
        #expect(messages == ["first", "second"])
    }

    @Test("migrated rows sort before new messages")
    func migratedRowsBeforeNewMessages() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()

        try await save(
            makeMessage(
                id: "legacy",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: now + 60_000,
                creationSource: .localDevice
            ),
            allocator: StubChatMessageOrderAllocator(value: 0)
        )
        try await save(
            makeMessage(id: "sent", origin: .user, status: .outgoing(.sent), timestamp: now)
        )

        let messages = try await feed(expectedCount: 2)
        #expect(messages == ["legacy", "sent"])
    }

    @Test("updating a message keeps its order")
    func updatingMessageKeepsOrder() async throws {
        try await seedChat()

        let now = Date().toChatTimestamp()

        try await save(
            makeMessage(
                id: "first",
                origin: .user,
                status: .outgoing(.new),
                timestamp: now
            )
        )
        try await save(
            makeMessage(
                id: "second",
                origin: .contact(alice.accountId),
                status: .incoming(.new),
                timestamp: now + 1_000
            )
        )

        try await save(
            makeMessage(
                id: "first",
                origin: .user,
                status: .outgoing(.sent),
                timestamp: now
            )
        )

        let messages = try await feed(expectedCount: 2)
        #expect(messages == ["first", "second"])
    }
}

private extension ChatMessageFeedOrderTests {
    func seedChat() async throws {
        try await facade.makeRepo(mapper: ChatContactMapper()).saveOperation({ [self.alice] }, { [] })
            .asyncExecute()
        try await facade.makeRepo(mapper: ChatModelMapper())
            .saveOperation({ [.newChatWithContact(self.alice)] }, { [] })
            .asyncExecute()
    }

    func save(
        _ message: Chat.LocalMessage,
        allocator: ChatMessageOrderAllocating? = nil
    ) async throws {
        try await facade.makeRepo(mapper: ChatMessageEntityMapper(orderAllocator: allocator ?? orderAllocator))
            .saveOperation({ [message] }, { [] })
            .asyncExecute()
    }

    func feed(expectedCount: Int) async throws -> [Chat.MessageId] {
        let factory = ChatMessageDataProviderFactory(
            repositoryFactory: ChatMessageRepositoryFactory(storageFacade: facade)
        )

        for try await messages in factory.subscribeChatMessages(.person(alice.accountId))
            where messages.count >= expectedCount {
            return messages.map(\.messageId)
        }

        return []
    }

    func lastMessageId() async throws -> Chat.MessageId? {
        let chats = try await facade.makeRepo(mapper: ChatModelMapper())
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()

        let aliceChatId = Chat.Id.person(alice.accountId)
        let aliceChat = chats.first { $0.identifier == aliceChatId.rawRepresentation }
        return aliceChat?.message?.messageId
    }

    func makeMessage(
        id: Chat.MessageId,
        origin: Chat.LocalMessage.Origin,
        status: Chat.LocalMessage.Status,
        timestamp: Chat.Timestamp,
        creationSource: Chat.LocalMessage.CreationSource = .localDevice
    ) -> Chat.LocalMessage {
        Chat.LocalMessage(
            messageId: id,
            chatId: .person(alice.accountId),
            origin: origin,
            creationSource: creationSource,
            status: status,
            timestamp: timestamp,
            content: .text(id),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )
    }
}
