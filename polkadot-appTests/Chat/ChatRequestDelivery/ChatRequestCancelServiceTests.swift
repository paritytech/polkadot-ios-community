@testable import polkadot_app
import BackgroundExecution
import Clocks
import CoreData
import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import Testing

struct ChatRequestCancelServiceTests {
    private let requestId = "request"
    private let peerAccountId = Data(repeating: 9, count: 32)
    private let identityKeyId = "//wallet//main"
    private let loader = StubPendingOutgoingChatRequestLoader(pending: nil)
    private let delivery = RecordingOutgoingChatRequestDelivery()
    private let builder = RecordingChatRequestStatementBuilder()
    private let signers = RecordingStatementSignerManager()
    private let store = MockChatRequestStoreService()
    private let cleanup = SpyChatRemovalCleanupService()

    @Test func publishesCancelWithOneShotKeyOfPublishedPeriod() async throws {
        let oneShot = try ChatKeyPaths.request(requestId: requestId, period: 20_000)
        let submitter = RecordingStatementStoreSubmitter()

        try await makeService(pending: makePending(period: 20_000), submitter: submitter).cancel(requestId: requestId)

        #expect(signers.requestedKeyIds == [oneShot])
        #expect(submitter.submitCount == 1)

        let cancel = try #require(builder.builtInputs.first)
        #expect(cancel.statementId == requestId)
        #expect(cancel.message.timestamp > 1)

        guard case .cancel = cancel.message.content else {
            Issue.record("Expected a cancel content")
            return
        }
    }

    @Test func alsoPublishesWithIdentityKeyWhenConsented() async throws {
        let oneShot = try ChatKeyPaths.request(requestId: requestId, period: 20_000)
        let submitter = RecordingStatementStoreSubmitter()

        try await makeService(pending: makePending(period: 20_000), consented: true, submitter: submitter)
            .cancel(requestId: requestId)

        #expect(signers.requestedKeyIds == [oneShot, identityKeyId])
        #expect(submitter.submitCount == 2)
    }

    @Test func skipsIdentityKeyWithoutConsent() async throws {
        let oneShot = try ChatKeyPaths.request(requestId: requestId, period: 20_000)

        try await makeService(pending: makePending(period: 20_000)).cancel(requestId: requestId)

        #expect(signers.requestedKeyIds == [oneShot])
    }

    @Test func noAllowanceOnOneShotSkipsItAndStillRemovesRequest() async throws {
        let submitter = RecordingStatementStoreSubmitter(failures: [StatementSubmitError.rejected(.noAllowance)])

        try await makeService(pending: makePending(period: 20_000), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 1)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
    }

    @Test func channelPriorityTooLowResubmitsOnceWithFreshExpiry() async throws {
        let submitter = RecordingStatementStoreSubmitter(
            failures: [StatementSubmitError.rejected(.channelPriorityTooLow)]
        )

        try await makeService(pending: makePending(period: 20_000), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 2)
        #expect(builder.builtInputs.count == 2)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
    }

    @Test func unpublishedRequestSkipsPublishesAndRemovesLocalData() async throws {
        let submitter = RecordingStatementStoreSubmitter()

        try await makeService(pending: makePending(period: nil), submitter: submitter).cancel(requestId: requestId)

        #expect(submitter.submitCount == 0)
        #expect(signers.requestedKeyIds.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func failedPublishReinstatesAndKeepsLocalData() async throws {
        let submitter = RecordingStatementStoreSubmitter(failures: [TestSubmitFailure()])
        let service = makeService(pending: makePending(period: 20_000), submitter: submitter)

        await #expect(throws: TestSubmitFailure.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(delivery.retired == [requestId])
        #expect(delivery.reinstated == [requestId])
        #expect(store.calls == [.markCancelling(requestId: requestId), .revertCancelling(requestId: requestId)])
        #expect(cleanup.accountIds.isEmpty)
    }

    @Test func successRetiresThenRemovesRequestAndCleansUpPeer() async throws {
        try await makeService(pending: makePending(period: 20_000)).cancel(requestId: requestId)

        #expect(delivery.retired == [requestId])
        #expect(delivery.reinstated.isEmpty)
        #expect(store.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(cleanup.accountIds == [peerAccountId])
    }

    @Test func readsPeriodAfterRetireSoRenewalDuringWaitIsSignedFor() async throws {
        let renewed = makePending(period: 20_001)
        let oneShot = try ChatKeyPaths.request(requestId: requestId, period: 20_001)
        delivery.onRetire = { [loader] in loader.setPending(renewed) }

        try await makeService(pending: makePending(period: 20_000)).cancel(requestId: requestId)

        #expect(signers.requestedKeyIds == [oneShot])
    }

    @Test func notPendingReinstatesWithoutPublishing() async throws {
        let submitter = RecordingStatementStoreSubmitter()
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
        let submitter = RecordingStatementStoreSubmitter()
        let failingStore = MockChatRequestStoreService(markCancellingError: ChatRequestCancelError.notPending)
        let service = makeService(pending: makePending(period: 20_000), submitter: submitter, store: failingStore)

        await #expect(throws: ChatRequestCancelError.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(delivery.retired.isEmpty)
        #expect(submitter.submitCount == 0)
        #expect(failingStore.calls == [.markCancelling(requestId: requestId)])
    }

    @Test func cancelRunsInsideBackgroundExecutor() async throws {
        let executor = CountingCancelExecutor()

        try await makeService(pending: makePending(period: 20_000), executor: executor).cancel(requestId: requestId)

        #expect(executor.executeCount == 1)
    }

    @Test func failureAfterPublishDoesNotRevert() async throws {
        let failingStore = MockChatRequestStoreService(deleteOutgoingError: TestSubmitFailure())
        let service = makeService(pending: makePending(period: 20_000), store: failingStore)

        await #expect(throws: TestSubmitFailure.self) {
            try await service.cancel(requestId: requestId)
        }

        #expect(failingStore.calls == [.markCancelling(requestId: requestId), .deleteOutgoing(requestId: requestId)])
        #expect(delivery.reinstated.isEmpty)
    }
}

private extension ChatRequestCancelServiceTests {
    func makeService(
        pending: PendingOutgoingRequest?,
        consented: Bool = false,
        submitter: RecordingStatementStoreSubmitter = RecordingStatementStoreSubmitter(),
        executor: BackgroundExecuting = InlineBackgroundExecutor(),
        store: MockChatRequestStoreService? = nil
    ) -> ChatRequestCancelService {
        loader.setPending(pending)

        return ChatRequestCancelService(
            dependencies: ChatRequestCancelDependencies(
                loader: loader,
                delivery: delivery,
                builder: builder,
                signerManager: signers,
                consentStore: StubChatSigningConsentStore(consented: consented),
                connection: submitter,
                removalCleanup: cleanup,
                requestStore: store ?? self.store,
                backgroundExecutor: executor
            ),
            clock: ImmediateClock()
        )
    }

    func makePending(period: UInt32?) -> PendingOutgoingRequest {
        PendingOutgoingRequest(
            input: OutgoingChatRequestInput(
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
            ),
            period: period
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
