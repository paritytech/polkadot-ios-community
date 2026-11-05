@testable import polkadot_app
import Foundation
import Testing

extension DeviceSyncExchangeTests {
    @Test("An outgoing message carries its local order, not its timestamp")
    func outgoingMessageCarriesLocalOrder() async throws {
        let peerAccountId = Data(repeating: 40, count: 32)
        let messageRepositoryFactory = MockChatMessageRepositoryFactory()
        try await messageRepositoryFactory.save([
            Chat.LocalMessage(
                messageId: "ordered-message",
                chatId: .person(Data(repeating: 41, count: 32)),
                origin: .user,
                creationSource: .localDevice,
                status: .outgoing(.sent),
                timestamp: 7_891,
                content: .text("hello"),
                reactions: [],
                compactionId: nil,
                relatedMessages: [],
                order: 42
            )
        ])
        let dataChannel = MockDeviceSyncPeerConnectionFlow(startResult: .success(()))
        let session = makeSession(
            peerAccountId: peerAccountId,
            flow: dataChannel,
            messageRepositoryFactory: messageRepositoryFactory
        )

        await session.start()
        await dataChannel.sendState(.connected)
        let sentUpdate = await dataChannel.waitForSentUpdate()

        let orders = sentUpdate.entities.flatMap { entity -> [UInt64] in
            guard case let .messages(messages) = entity else { return [] }
            return messages.map(\.order)
        }
        #expect(orders == [42])

        await session.close()
    }
}
