@testable import polkadot_app
import Foundation
import Keystore_iOS
import Operation_iOS
import SubstrateSdk
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferReceiverRulesTests {
    private let world = TransferStateTestWorld()
    private let allocator = InMemoryChatMessageOrderAllocator()

    init() async throws {
        try await world.setup()
    }

    @Test("Transferred messages keep the sender's order, and a message written afterwards sorts after them")
    func transferredMessagesKeepSenderOrder() async throws {
        try await saveTransferred([makeMessage("first", order: 50), makeMessage("second", order: 70)])
        try await saveLocal(makeMessage("local", order: 0, creationSource: .localDevice))

        let orders = try await storedOrders()
        #expect(orders["first"] == 50)
        #expect(orders["second"] == 70)
        #expect(try #require(orders["local"]) > 70)
    }

    @Test("A contact's acceptance adds its device even without the request it answers", arguments: [true, false])
    func acceptanceDeviceWithoutRequest(fromContact: Bool) async throws {
        let device = Chat.PeerDevice(
            statementAccountId: Data(repeating: 0x21, count: 32),
            encryptionPublicKey: Data(repeating: 0x22, count: 32)
        )
        let contacts = ContactsLocalStorageService(storageFacade: world.facade, logger: MockLogger())
        let applier = DeviceSyncChatAcceptedApplier(
            storageFacade: world.facade,
            contactsStorageService: contacts,
            peerLogger: MockLogger()
        )

        try await applier.apply([makeAcceptance(device: device, fromContact: fromContact)])

        let stored = try await contacts.getContact(by: peerAccountId()).asyncExecute()
        #expect(stored?.devices == (fromContact ? [device] : []))
    }

    @Test("The checkpoint belongs to the sender installation that set it")
    func checkpointIsPerSender() {
        let store = DeviceTransferCheckpointStore(settingsManager: InMemorySettingsManager())
        let sender = Data(repeating: 0x01, count: 32)

        store.save(1_000, senderInstallationId: sender)

        #expect(store.checkpoint(for: sender) == 1_000)
        #expect(store.checkpoint(for: Data(repeating: 0x02, count: 32)) == nil)
        store.clear()
        #expect(store.checkpoint(for: sender) == nil)
    }
}

private extension DeviceTransferReceiverRulesTests {
    func peerAccountId() throws -> Data {
        try #require(world.chatManager.chatId.accountId)
    }

    func makeMessage(
        _ messageId: String,
        order: UInt64,
        creationSource: Chat.LocalMessage.CreationSource = .deviceSync
    ) -> Chat.LocalMessage {
        Chat.LocalMessage(
            messageId: messageId,
            chatId: world.chatManager.chatId,
            origin: .user,
            creationSource: creationSource,
            status: .outgoing(.sent),
            timestamp: 1_000 + order,
            content: .text(messageId),
            reactions: [],
            compactionId: nil,
            relatedMessages: [],
            order: order
        )
    }

    func makeAcceptance(device: Chat.PeerDevice, fromContact: Bool) throws -> Chat.DeviceSyncWireMessage {
        try Chat.DeviceSyncWireMessage(
            remote: Chat.RemoteMessage(
                messageId: "acceptance",
                timestamp: 2_000,
                versioned: .v1(Chat.RemoteMessageContentV1(
                    content: .multiChatAccepted(.init(requestId: "never-seen-here", device: device))
                ))
            ),
            peerId: peerAccountId(),
            status: fromContact ? .incoming(.seen) : .outgoing(.delivered),
            order: 1
        )
    }

    func saveTransferred(_ messages: [Chat.LocalMessage]) async throws {
        try await SenderOrderChatMessageRepositoryFactory(storageFacade: world.facade, orderAllocator: allocator)
            .createRepository(forFilter: nil)
            .saveOperation({ messages }, { [] })
            .asyncExecute()
    }

    func saveLocal(_ message: Chat.LocalMessage) async throws {
        try await world.facade
            .createRepository(mapper: AnyCoreDataMapper(ChatMessageEntityMapper(orderAllocator: allocator)))
            .saveOperation({ [message] }, { [] })
            .asyncExecute()
    }

    func storedOrders() async throws -> [String: UInt64] {
        let messages = try await ChatMessageRepositoryFactory(storageFacade: world.facade)
            .createRepository(forFilter: nil)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
        return Dictionary(uniqueKeysWithValues: messages.map { ($0.messageId, $0.order) })
    }
}
