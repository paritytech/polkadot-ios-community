import Foundation
import MessageExchangeKit
import SubstrateSdk
import Testing
@testable import polkadot_app

struct ChatRequestRenewerTests {
    private let allocator = StubNotificationAllocator()
    private let store = InMemoryChatRequestRenewalStore()
    private let outgoingService = RecordingOutgoingChatRequestService()
    private let issueReporter = RecordingIssueReporter()
    private let signers =
        ChatRequestDeliverySigners(signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager()))

    @Test func renewsRequestOfEarlierPeriodFromFreshAccount() async throws {
        store.candidates = [candidate("request", period: 99)]
        let fresh = try account("request", period: 100)

        await makeRenewer().renew()

        #expect(allocator.initiatedTargets == [fresh])
        #expect(outgoingService.sentSigners == [fresh])
        #expect(store.periodUpdates.map(\.period) == [100])
    }

    @Test func leavesStaleRequestOnItsOldCopyWhenNoSlotIsClaimed() async {
        allocator.hasFreeSlot = false
        store.candidates = [candidate("request", period: 99)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners.isEmpty)
        #expect(store.periodUpdates.isEmpty)
    }

    @Test func renewsNewestRequestsFirstWhenSlotsRunShort() async throws {
        allocator.freeSlotCount = 1
        store.candidates = [candidate("newer", period: 99), candidate("older", period: 99)]

        await makeRenewer().renew()

        #expect(try outgoingService.sentSigners == [account("newer", period: 100)])
    }

    @Test func resendsRequestOfCurrentPeriodMissingFromStore() async throws {
        store.candidates = [candidate("request", period: 100)]

        await makeRenewer().renew()

        #expect(try outgoingService.sentSigners == [account("request", period: 100)])
        #expect(allocator.initiatedTargets.isEmpty)
        #expect(store.periodUpdates.isEmpty)
    }

    @Test func leavesRequestOfCurrentPeriodAloneWhileStored() async throws {
        store.candidates = [candidate("request", period: 100)]
        outgoingService.storedSigners = try [account("request", period: 100)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners.isEmpty)
    }

    @Test func reportsRenewalThatClaimedSlotButFailedToPublish() async {
        store.candidates = [candidate("request", period: 99)]
        outgoingService.failures = [TestRenewalError()]

        await makeRenewer().renew()

        #expect(issueReporter.kinds == ["renewal-publish-failed"])
        #expect(store.periodUpdates.isEmpty)
    }

    @Test func reportsRequestsLeftUnrenewedPastTheirPeriod() async {
        allocator.hasFreeSlot = false
        store.candidates = [candidate("starved", period: 98), candidate("recent", period: 99)]

        await makeRenewer().renew()

        #expect(issueReporter.kinds == ["renewal-starved"])
    }

    @Test func reportsRenewalFailingRunAfterRun() async {
        store.readError = TestRenewalError()
        let renewer = makeRenewer()

        for _ in 0 ..< ChatRequestDiagnostics.failingRenewalRuns + 1 {
            await renewer.renew()
        }

        #expect(issueReporter.kinds == ["renewal-failing"])
    }

    private func makeRenewer() -> ChatRequestRenewer {
        ChatRequestRenewer(
            store: store,
            allocator: allocator,
            signers: signers,
            outgoingService: outgoingService,
            diagnostics: ChatRequestDiagnostics(logger: MockLogger(), issueReporter: issueReporter)
        )
    }

    private func account(_ requestId: String, period: UInt32) throws -> AccountId {
        try signers.anonymous(requestId: requestId, period: period).signer.accountId
    }

    private func candidate(_ requestId: String, period: UInt32) -> ChatRequestRenewalCandidate {
        ChatRequestRenewalCandidate(
            message: Chat.RequestMessage(
                messageId: requestId,
                timestamp: 1,
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            session: MessageExchange.SessionRequest(
                own: MessageExchange.Own(signKeyId: "//wallet//main", encryptionKeyId: "main", pin: nil),
                peer: MessageExchange.Peer(
                    accountId: Data(repeating: 9, count: 32),
                    publicKey: Data(repeating: 8, count: 32),
                    pin: nil,
                    devices: []
                )
            ),
            period: period
        )
    }
}

private struct TestRenewalError: Error {}
