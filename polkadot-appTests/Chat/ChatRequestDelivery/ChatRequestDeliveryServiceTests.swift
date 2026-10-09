import Clocks
import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import Testing
@testable import polkadot_app

struct ChatRequestDeliveryServiceTests {
    private let message = Chat.RequestMessage(
        messageId: "request",
        timestamp: 1,
        content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
    )
    private let session = MessageExchange.SessionRequest(
        own: MessageExchange.Own(signKeyId: "//wallet//main", encryptionKeyId: "main", pin: nil),
        peer: MessageExchange.Peer(
            accountId: Data(repeating: 9, count: 32),
            publicKey: Data(repeating: 8, count: 32),
            pin: nil,
            devices: []
        )
    )
    private let outgoingService = RecordingOutgoingChatRequestService()
    private let store = InMemoryChatRequestDeliveryStore()
    private let signer: ChatRequestDeliverySigner

    init() throws {
        let signManager = ChatSignerManager(entropyManager: FixedRootEntropyManager())
        signer = try ChatRequestDeliverySigners(signManager: signManager).anonymous(requestId: "request", period: 7)
    }

    @Test func publishesWithResolvedSignerAndRecordsItsPeriod() async {
        await makeService().deliverUntilDone(message, session: session)

        #expect(outgoingService.sentSigners == [signer.signer.accountId])
        #expect(store.delivered.map(\.anonymousPeriod) == [7])
    }

    @Test func doesNotPublishRequestNoLongerAwaitingDelivery() async {
        store.isAwaiting = false

        await makeService().deliverUntilDone(message, session: session)

        #expect(outgoingService.sentSigners.isEmpty)
        #expect(store.delivered.isEmpty)
    }

    @Test func retriesFailedAttemptUntilDelivered() async {
        outgoingService.failures = [TestDeliveryError(), TestDeliveryError()]

        await makeService().deliverUntilDone(message, session: session)

        #expect(outgoingService.sentSigners.count == 1)
        #expect(store.delivered.count == 1)
    }

    @Test func stopsRetryingOnceRequestNoLongerAwaitsDelivery() async {
        outgoingService.failures = Array(repeating: TestDeliveryError(), count: 10)
        store.awaitingReadsLeft = 2

        await makeService().deliverUntilDone(message, session: session)

        #expect(outgoingService.failures.count == 8)
        #expect(store.delivered.isEmpty)
    }

    private func makeService() -> ChatRequestDeliveryService {
        ChatRequestDeliveryService(
            outgoingService: outgoingService,
            resolver: StubDeliveryAccountResolver(signer: signer),
            store: store,
            clock: ImmediateClock(),
            logger: MockLogger()
        )
    }
}

private struct TestDeliveryError: Error {}
