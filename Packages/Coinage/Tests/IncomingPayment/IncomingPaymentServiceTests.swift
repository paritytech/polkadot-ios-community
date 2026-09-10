import Testing
import Foundation
import AsyncExtensions
@testable import Coinage

struct IncomingPaymentServiceTests {
    private func makeService(
        store: InMemoryIncomingPaymentStore,
        secretStore: InMemoryIncomingPaymentSecretStore = InMemoryIncomingPaymentSecretStore(),
        resolver: StubSourceResolver = StubSourceResolver(),
        acknowledger: StubAcknowledger = StubAcknowledger()
    ) -> IncomingPaymentService {
        IncomingPaymentService(
            store: store,
            secretStore: secretStore,
            sourceResolver: resolver,
            paymentContext: IncomingPaymentContext(logger: StubLogger()),
            claimCoinsService: StubClaimCoinsService(),
            claimAssetService: StubClaimAssetService(),
            txService: StubCoinageTxServicing(),
            contextProvider: StubDenominationContextProvider(),
            acknowledger: acknowledger,
            instanceId: 0,
            logger: StubLogger()
        )
    }

    @Test func acceptPersistsRecordAndSecret() async throws {
        let store = InMemoryIncomingPaymentStore()
        let secretStore = InMemoryIncomingPaymentSecretStore()
        let service = makeService(store: store, secretStore: secretStore)

        try await service.accept(
            amount: 100,
            descriptor: .coins(secretKeys: [Data([0x01])]),
            paymentId: "p1",
            productId: "prod"
        )

        let saved = try #require(store.payment(for: "top up:prod:p1"))
        #expect(saved.amount == 100)
        #expect(saved.outcome == nil)
        #expect(saved.groupId == "top up:prod:p1")
        #expect(secretStore.hasDescriptor(for: "top up:prod:p1"))
    }

    @Test func acceptRejectsDuplicateGroupId() async throws {
        let existing = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: nil
        )
        let store = InMemoryIncomingPaymentStore(seed: [existing])
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 100,
                descriptor: .coins(secretKeys: [Data([0x01])]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { ($0 as? IncomingPaymentError) == .alreadyExists }
    }

    @Test func acceptRejectsBusySource() async throws {
        let active = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: nil
        )
        let store = InMemoryIncomingPaymentStore(seed: [active])
        let secretStore = InMemoryIncomingPaymentSecretStore(
            seed: ["top up:prod:p1": .coins(secretKeys: [Data([0x05])])]
        )
        let service = makeService(store: store, secretStore: secretStore)

        await #expect {
            try await service.accept(
                amount: 50,
                descriptor: .coins(secretKeys: [Data([0x05])]),
                paymentId: "p2",
                productId: "prod"
            )
        } throws: { ($0 as? IncomingPaymentError) == .sourceBusy }
    }

    @Test func settledSourceIsNotBusy() async throws {
        let done = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: .claimed
        )
        // A settled payment has no live secret — it was wiped on settle.
        let store = InMemoryIncomingPaymentStore(seed: [done])
        let service = makeService(store: store)

        // Reusing a source whose only prior payment is terminal is allowed.
        try await service.accept(
            amount: 50,
            descriptor: .coins(secretKeys: [Data([0x06])]),
            paymentId: "p2",
            productId: "prod"
        )
        #expect(store.payment(for: "top up:prod:p2") != nil)
    }

    @Test func acceptRejectsInvalidSource() async throws {
        let store = InMemoryIncomingPaymentStore()
        let service = makeService(store: store, resolver: StubSourceResolver(shouldFail: true))

        await #expect {
            try await service.accept(
                amount: 10,
                descriptor: .privateKey(secretKey: Data([0x00])),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { Self.isInvalidSource($0) }
    }

    @Test func rejectedAcceptLeavesNoSecretBehind() async throws {
        let store = InMemoryIncomingPaymentStore()
        let secretStore = InMemoryIncomingPaymentSecretStore()
        let service = makeService(
            store: store,
            secretStore: secretStore,
            resolver: StubSourceResolver(shouldFail: true)
        )

        _ = try? await service.accept(
            amount: 10,
            descriptor: .privateKey(secretKey: Data([0x00])),
            paymentId: "p1",
            productId: "prod"
        )
        #expect(!secretStore.hasDescriptor(for: "top up:prod:p1"))
    }

    @Test func acceptMapsUnexpectedFailureToUnknown() async throws {
        let store = InMemoryIncomingPaymentStore()
        store.fetchError = InMemoryIncomingPaymentStore.Failure()
        let service = makeService(store: store)

        await #expect {
            try await service.accept(
                amount: 10,
                descriptor: .coins(secretKeys: [Data([0x07])]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { Self.isUnknown($0) }
    }

    @Test func coldSubscribeReturnsStoredVerdictExactly() async throws {
        let settled = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: .claimedPartially(actualClaimed: 42)
        )
        let store = InMemoryIncomingPaymentStore(seed: [settled])
        let service = makeService(store: store)

        let stream = await service.subscribeStatus(for: "p1", productId: "prod")
        var observed: IncomingPaymentStatus?
        for try await status in stream {
            observed = status
            break
        }
        #expect(observed == .claimedPartially(actualClaimed: 42))
    }

    @Test func coldSubscribeToUnknownPaymentReportsNotClaimed() async throws {
        let store = InMemoryIncomingPaymentStore()
        let service = makeService(store: store)

        let stream = await service.subscribeStatus(for: "ghost", productId: "prod")
        var observed: IncomingPaymentStatus?
        for try await status in stream {
            observed = status
            break
        }
        #expect(observed == .notClaimed)
    }

    @Test(.timeLimit(.minutes(1)))
    func partialOutcomeIsAcknowledgedAndPersisted() async throws {
        let acknowledger = StubAcknowledger()
        let (service, store) = makeDrivingService(
            detections: [.claiming, .claimedPartially(claimed: 40)],
            acknowledger: acknowledger
        )

        service.setup()
        try await waitUntil { acknowledger.calls().count == 1 }
        service.throttle()

        let call = try #require(acknowledger.calls().first)
        #expect(call.outcome == .claimedPartially(actualClaimed: 40))
        #expect(call.requestedAmount == 100)
        #expect(store.payment(for: "top up:prod:p")?.outcome == .claimedPartially(actualClaimed: 40))
    }

    @Test(.timeLimit(.minutes(1)))
    func notClaimedOutcomeIsAcknowledged() async throws {
        let acknowledger = StubAcknowledger()
        let (service, store) = makeDrivingService(detections: [.notClaimed], acknowledger: acknowledger)

        service.setup()
        try await waitUntil { store.payment(for: "top up:prod:p")?.outcome == .notClaimed }
        service.throttle()

        #expect(acknowledger.calls().map(\.outcome) == [.notClaimed])
    }

    @Test(.timeLimit(.minutes(1)))
    func claimedOutcomeIsNotAcknowledged() async throws {
        let acknowledger = StubAcknowledger()
        let (service, store) = makeDrivingService(
            detections: [.claimed(amount: 100, finalized: true)],
            acknowledger: acknowledger
        )

        service.setup()
        try await waitUntil { store.payment(for: "top up:prod:p")?.outcome == .claimed }
        service.throttle()

        #expect(acknowledger.calls().isEmpty)
    }

    /// A service wired to drive one seeded `(prod, p)` payment (secret present, coins source) through a
    /// canned detection sequence to settlement.
    private func makeDrivingService(
        detections: [CoinageTransferDetection],
        acknowledger: StubAcknowledger
    ) -> (IncomingPaymentService, InMemoryIncomingPaymentStore) {
        let payment = IncomingPayment(
            paymentId: "p",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: nil
        )
        let store = InMemoryIncomingPaymentStore(seed: [payment])
        let secretStore = InMemoryIncomingPaymentSecretStore(
            seed: ["top up:prod:p": .coins(secretKeys: [Data([0x01])])]
        )
        let service = IncomingPaymentService(
            store: store,
            secretStore: secretStore,
            sourceResolver: StubSourceResolver(),
            paymentContext: IncomingPaymentContext(logger: StubLogger()),
            claimCoinsService: StubClaimCoinsService(detections: detections),
            claimAssetService: StubClaimAssetService(),
            txService: StubCoinageTxServicing(),
            contextProvider: WorkingDenominationContextProvider(),
            acknowledger: acknowledger,
            instanceId: 0,
            logger: StubLogger()
        )
        return (service, store)
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func isInvalidSource(_ error: any Error) -> Bool {
        guard let error = error as? IncomingPaymentError, case .invalidSource = error else { return false }
        return true
    }

    private static func isUnknown(_ error: any Error) -> Bool {
        guard let error = error as? IncomingPaymentError, case .unknown = error else { return false }
        return true
    }
}
