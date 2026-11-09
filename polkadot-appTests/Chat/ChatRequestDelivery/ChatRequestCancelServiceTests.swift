@testable import polkadot_app
import BackgroundExecution
import Clocks
import CoreData
import Foundation
import MessageExchangeKit
import StatementStore
import StructuredConcurrencyTestSupport
import SubstrateSdk
import Testing

struct ChatRequestCancelServiceTests {
    private let requestId = "request"
    private let peerAccountId = Data(repeating: 9, count: 32)
    private let identityKeyId = "//wallet//main"
    private let timestampPriority: UInt64 = 0xFFFF_FFFF_0000_0100
    private let currentPeriod: UInt32 = 100
    private let loader = StubPendingOutgoingChatRequestLoader(pending: nil)
    private let delivery = RecordingOutgoingChatRequestDelivery()
    private let builder = RecordingChatRequestStatementBuilder()
    private let signers = RecordingStatementSignerManager()
    private let store = MockChatRequestStoreService()
    private let cleanup = SpyChatRemovalCleanupService()
    private let periodProvider = StubNotificationAllocator()

    init() {
        periodProvider.period = currentPeriod
    }

    @Test func publishesOneCancelPerLiveCopyWithItsOwnKey() async throws {
        let currentKeyId = try ChatKeyPaths.request(requestId: requestId, period: currentPeriod)
        let previousKeyId = try ChatKeyPaths.request(requestId: requestId, period: currentPeriod - 1)
        let submitter = try RecordingStatementStoreConnection(stored: [
            storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1),
            storedCopy(signedBy: currentKeyId, expiry: timestampPriority + 2),
            storedCopy(signedBy: previousKeyId, expiry: timestampPriority + 3)
        ])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(signers.requestedKeyIds == [identityKeyId, currentKeyId, previousKeyId])
        #expect(submitter.submitCount == 3)
        #expect(submitter.submittedSenders == [
            RecordingStatementSignerManager.accountId(for: identityKeyId),
            RecordingStatementSignerManager.accountId(for: currentKeyId),
            RecordingStatementSignerManager.accountId(for: previousKeyId)
        ])
        #expect(builder.builtExpiries == [timestampPriority + 2, timestampPriority + 3, timestampPriority + 4])
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
    }

    @Test func copyFromUnknownAccountIsSkipped() async throws {
        let stranger = try storedCopy(signedBy: "stranger", expiry: timestampPriority + 5)
        let submitter = RecordingStatementStoreConnection(stored: [stranger])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 0)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
    }

    @Test func noAllowanceCopyCountsAsDone() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(
            failures: [StatementSubmitError.rejected(.noAllowance)],
            stored: [copy]
        )

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 1)
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func accountFullOnOnlyCopyRevertsAndReinstates() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(
            failures: [StatementSubmitError.rejected(.accountFull)],
            stored: [copy]
        )
        let service = makeService(pending: makePending(), submitter: submitter)

        await #expect(throws: StatementSubmitError.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(submitter.submitCount == 1)
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
        #expect(delivery.reinstated == [requestId])
        #expect(cleanup.accountIds.isEmpty)
    }

    @Test func oneAcceptedAndOneFailedRemovesRequestLocally() async throws {
        let identityCopy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let currentKeyId = try ChatKeyPaths.request(requestId: requestId, period: currentPeriod)
        let currentCopy = try storedCopy(signedBy: currentKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(
            failures: [StatementSubmitError.rejected(.accountFull)],
            stored: [identityCopy, currentCopy]
        )

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 2)
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func emptyFetchRemovesLocalDataWithoutPublishing() async throws {
        let submitter = RecordingStatementStoreConnection()

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 0)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func cancelExpiryExceedsOwnCopyOnChannel() async throws {
        let oneShotKeyId = try ChatKeyPaths.request(requestId: requestId, period: currentPeriod)
        let stored = try storedCopy(signedBy: oneShotKeyId, expiry: timestampPriority + 10)
        let submitter = RecordingStatementStoreConnection(stored: [stored])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(builder.builtExpiries == [timestampPriority + 11])
    }

    @Test func cancelExpiryUsesTimestampWhenCopyExpiryIsOlder() async throws {
        let oneShotKeyId = try ChatKeyPaths.request(requestId: requestId, period: currentPeriod)
        let stored = try storedCopy(signedBy: oneShotKeyId, expiry: timestampPriority - 10)
        let submitter = RecordingStatementStoreConnection(stored: [stored])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(builder.builtExpiries == [timestampPriority])
    }

    @Test func identityCopyIsCancelledWithIdentityKeyAndExpiry() async throws {
        let stored = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 7)
        let submitter = RecordingStatementStoreConnection(stored: [stored])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(builder.builtExpiries == [timestampPriority + 8])
        #expect(submitter.fetchCount == 1)
    }

    @Test func fetchFailureRevertsWithoutPublishing() async throws {
        let submitter = RecordingStatementStoreConnection(fetchFailure: TestSubmitFailure())
        let service = makeService(pending: makePending(), submitter: submitter)

        await #expect(throws: TestSubmitFailure.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(submitter.submitCount == 0)
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
    }

    @Test func failedPublishReinstatesAndKeepsLocalData() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(
            failures: [TestSubmitFailure(), TestSubmitFailure(), TestSubmitFailure()],
            stored: [copy]
        )
        let service = makeService(pending: makePending(), submitter: submitter)

        await #expect(throws: TestSubmitFailure.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(submitter.submitCount == 3)
        #expect(delivery.retired == [requestId])
        #expect(delivery.reinstated == [requestId])
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
        #expect(cleanup.accountIds.isEmpty)
    }

    @Test func channelPriorityTooLowIsRetriedWithFreshCancel() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(
            failures: [StatementSubmitError.rejected(.channelPriorityTooLow)],
            stored: [copy]
        )

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 2)
        #expect(builder.builtExpiries.count == 2)
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func networkErrorIsRetriedAndSucceeds() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(failures: [TestSubmitFailure()], stored: [copy])

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 2)
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
    }

    @Test(.timeLimit(.minutes(1))) func retryDelaysAreOneThenTwoSeconds() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let rejection = StatementSubmitError.rejected(.channelPriorityTooLow)
        let submitter = RecordingStatementStoreConnection(failures: [rejection, rejection, rejection], stored: [copy])
        let clock = ManualClock()
        let service = makeService(pending: makePending(), submitter: submitter, clock: clock)
        let cancellation = Task { try await service.cancel(requestId: requestId) }

        await clock.resumeSleep(for: .seconds(1))
        await clock.resumeSleep(for: .seconds(2))

        await #expect(throws: StatementSubmitError.self) {
            try await cancellation.value
        }

        #expect(submitter.submitCount == 3)
        #expect(delivery.reinstated == [requestId])
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
    }

    @Test func timeoutIsNotRetried() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(failures: [JSONRPCOperationError.timeout], stored: [copy])
        let service = makeService(pending: makePending(), submitter: submitter)

        await #expect(throws: JSONRPCOperationError.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(submitter.submitCount == 1)
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
    }

    @Test func successRetiresThenRemovesRequestAndCleansUpPeer() async throws {
        try await makeService(pending: makePending()).cancel(requestId: requestId)

        #expect(delivery.retired == [requestId])
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func readsPendingAfterRetireSoPublishDuringWaitIsCancelled() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(stored: [copy])
        delivery.onRetire = { [loader] in loader.setPending(makePending()) }

        try await makeService(pending: makePending(), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 1)
    }

    @Test func cancelProofBindsCancelledRequestId() async throws {
        try await makeService(pending: makePending()).cancel(requestId: requestId)

        #expect(store.cancelProofRequestIds == [requestId])
    }

    @Test func notPendingReinstatesWithoutPublishing() async throws {
        let submitter = RecordingStatementStoreConnection()
        let service = makeService(pending: nil, submitter: submitter)

        await #expect(throws: ChatRequestCancelError.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(delivery.retired == [requestId])
        #expect(delivery.reinstated == [requestId])
        #expect(submitter.submitCount == 0)
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
    }

    @Test func markNotPendingThrowsWithoutRetiringOrPublishing() async throws {
        let submitter = RecordingStatementStoreConnection()
        let failingStore = MockChatRequestStoreService(markCancellingError: ChatRequestCancelError.notPending)
        let service = makeService(pending: makePending(), submitter: submitter, store: failingStore)

        await #expect(throws: ChatRequestCancelError.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(delivery.retired.isEmpty)
        #expect(submitter.submitCount == 0)
        #expect(failingStore.calls == [.markCancelling(requestId: requestId)])
    }

    @Test func cancelRunsInsideBackgroundExecutor() async throws {
        let executor = CountingCancelExecutor()

        try await makeService(pending: makePending(), executor: executor).cancel(requestId: requestId)

        #expect(executor.executeCount == 1)
    }

    @Test func failureAfterPublishDoesNotRevert() async throws {
        let copy = try storedCopy(signedBy: identityKeyId, expiry: timestampPriority + 1)
        let submitter = RecordingStatementStoreConnection(stored: [copy])
        let failingStore = MockChatRequestStoreService(deleteOutgoingError: TestSubmitFailure())
        let service = makeService(pending: makePending(), submitter: submitter, store: failingStore)

        await #expect(throws: TestSubmitFailure.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(failingStore.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(delivery.reinstated.isEmpty)
    }
}

private extension ChatRequestCancelServiceTests {
    func makeService(
        pending: OutgoingChatRequestInput?,
        submitter: RecordingStatementStoreConnection = RecordingStatementStoreConnection(),
        executor: BackgroundExecuting = InlineBackgroundExecutor(),
        store: MockChatRequestStoreService? = nil,
        clock: any Clock<Duration> = ImmediateClock()
    ) -> ChatRequestCancelService {
        loader.setPending(pending)

        return ChatRequestCancelService(
            dependencies: ChatRequestCancelDependencies(
                loader: loader,
                delivery: delivery,
                builder: builder,
                signerManager: signers,
                periodProvider: periodProvider,
                connection: submitter,
                priorityFactory: FixedStatementPriorityFactory(timestampPriority: timestampPriority),
                removalCleanup: cleanup,
                requestStore: store ?? self.store,
                backgroundExecutor: executor,
                logger: StubLogger(),
                clock: clock
            )
        )
    }

    func storedCopy(signedBy keyId: String, expiry: UInt64) throws -> Data {
        try UnsignedStatement()
            .addExpiry(expiry)
            .signed(by: StubStatementSigner(accountId: RecordingStatementSignerManager.accountId(for: keyId)))
            .build()
            .encodedStatement
    }

    func makePending() -> OutgoingChatRequestInput {
        OutgoingChatRequestInput(
            message: Chat.RequestMessage(
                messageId: requestId,
                timestamp: 1,
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            session: MessageExchange.SessionRequest(
                own: .init(signKeyId: identityKeyId, encryptionKeyId: "main", pin: nil),
                peer: .init(
                    accountId: peerAccountId,
                    publicKey: Data(repeating: 1, count: 32),
                    pin: nil,
                    devices: []
                )
            )
        )
    }
}

struct ChatRequestOutgoingDeletionTests {
    private let facade = UserDataStorageTestFacade()
    private let requestId = "request"
    private let peerAccountId = Data(repeating: 9, count: 32)

    @Test func deletesContactChatRequestAndPublicationTogether() async throws {
        try await insertOutgoingRequest()

        try await facade.databaseService.performWrite { [requestId] context in
            try context.deleteOutgoingChatRequest(requestId)
        }

        let remaining: (contact: Bool, chat: Bool, request: Bool, period: UInt32?) = try await facade.databaseService
            .performRead { [requestId, peerAccountId] context in
                let contact: CDChatContact? = try context.first(for: .contact(for: peerAccountId))
                let chat: CDChat? = try context.first(for: .chatWithContact(for: peerAccountId))
                let fetchRequest = CDChatRequest.fetchRequest()
                fetchRequest.predicate = .chatRequestById(requestId)
                let request = try context.fetch(fetchRequest).first

                return try (
                    contact != nil,
                    chat != nil,
                    request != nil,
                    context.outgoingStatementPeriod(for: requestId)
                )
            }

        #expect(!remaining.contact)
        #expect(!remaining.chat)
        #expect(!remaining.request)
        #expect(remaining.period == nil)
    }
}

private extension ChatRequestOutgoingDeletionTests {
    func insertOutgoingRequest() async throws {
        try await facade.databaseService.performWrite { [requestId, peerAccountId] context in
            let contact = CDChatContact(context: context)
            contact.identifier = peerAccountId.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 1, count: 32)

            let chat = CDChat(context: context)
            chat.identifier = Chat.Id.person(peerAccountId).rawRepresentation

            let message = CDChatMessage(context: context)
            message.messageId = requestId
            message.status = Chat.LocalMessage.Status.outgoing(.new).rawValue

            let request = CDChatRequest(context: context)
            request.identifier = requestId
            request.status = Chat.RequestStatus.outgoing(.pending).rawValue
            request.contactId = peerAccountId.toHex()
            request.message = message
            request.contact = contact
            contact.chatRequest = request

            try context.setOutgoingStatementPeriod(20_000, for: requestId)
        }
    }
}

private struct TestSubmitFailure: Error {}

private final class CountingCancelExecutor: BackgroundExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedExecuteCount = 0

    var executeCount: Int {
        lock.withLock { recordedExecuteCount }
    }

    func execute<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        lock.withLock { recordedExecuteCount += 1 }
        return try await operation()
    }
}
