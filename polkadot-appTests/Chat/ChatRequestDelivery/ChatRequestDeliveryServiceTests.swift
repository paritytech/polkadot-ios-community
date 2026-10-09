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
    private let resolver: StubDeliveryAccountResolver
    private let issueReporter = RecordingIssueReporter()

    init() throws {
        let signManager = ChatSignerManager(entropyManager: FixedRootEntropyManager())
        signer = try ChatRequestDeliverySigners(signManager: signManager).anonymous(requestId: "request", period: 7)
        resolver = StubDeliveryAccountResolver(signer: signer)
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

    @Test func marksOversizedRequestFailedWithoutClaimingSlot() async {
        outgoingService.encodedSize = resolver.statementSize + 1

        await makeService().deliverUntilDone(message, session: session)

        #expect(store.failed == ["request"])
        #expect(resolver.resolvedCount == 0)
        #expect(outgoingService.sentSigners.isEmpty)
        #expect(issueReporter.kinds == ["oversized-request"])
    }

    @Test func deliversRequestThatExactlyFitsStatementLimit() async {
        outgoingService.encodedSize = resolver.statementSize

        await makeService().deliverUntilDone(message, session: session)

        #expect(store.delivered.count == 1)
        #expect(store.failed.isEmpty)
    }

    @Test func reportsDeliveryStalledAfterAttemptThreshold() async {
        let stalled = ChatRequestDiagnostics.stalledDeliveryAttempts
        outgoingService.failures = Array(repeating: TestDeliveryError(), count: stalled + 2)

        await makeService().deliverUntilDone(message, session: session)

        #expect(issueReporter.kinds == ["delivery-stalled"])
        #expect(store.delivered.count == 1)
    }

    @Test func doesNotReportTransientFailures() async {
        outgoingService.failures = [TestDeliveryError(), TestDeliveryError()]

        await makeService().deliverUntilDone(message, session: session)

        #expect(issueReporter.kinds.isEmpty)
    }

    private func makeService() -> ChatRequestDeliveryService {
        ChatRequestDeliveryService(
            outgoingService: outgoingService,
            resolver: resolver,
            store: store,
            execution: ChatRequestDeliveryExecution(
                backgroundExecutor: InlineBackgroundExecutor(),
                clock: ImmediateClock()
            ),
            diagnostics: ChatRequestDiagnostics(logger: MockLogger(), issueReporter: issueReporter)
        )
    }
}

private struct TestDeliveryError: Error {}
