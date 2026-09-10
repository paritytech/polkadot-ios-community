import Testing
import Foundation
import AsyncExtensions
@testable import Coinage

struct IncomingPaymentServiceTests {
    /// Inert denomination context — the claim stubs ignore it; it only exists to drive `setup(with:)`.
    private static let denomination = DenominationBreakdownContext(
        unit: 1,
        precision: 10,
        maxExponent: 0,
        minExponent: 0
    )

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
            verdictResolver: StubGroupVerdictResolver(verdict: .notClaimed),
            acknowledger: acknowledger,
            instanceId: 0,
            logger: StubLogger()
        )
    }

    @Test func acceptRejectsZeroAmount() async throws {
        let store = InMemoryIncomingPaymentStore()
        let secretStore = InMemoryIncomingPaymentSecretStore()
        let service = makeService(store: store, secretStore: secretStore)

        await #expect {
            try await service.accept(
                amount: 0,
                descriptor: .coins(secretKeys: [Data([0x01])]),
                paymentId: "p1",
                productId: "prod"
            )
        } throws: { ($0 as? IncomingPaymentError) == .invalidAmount }
        #expect(store.payment(for: "top up:prod:p1") == nil)
        #expect(!secretStore.hasDescriptor(for: "top up:prod:p1"))
    }

    @Test func acceptFailsWhenBusyCheckCannotReadSecrets() async throws {
        let active = IncomingPayment(
            paymentId: "p1",
            productId: "prod",
            amount: 100,
            createdAt: Date(),
            outcome: nil
        )
        let store = InMemoryIncomingPaymentStore(seed: [active])
        let secretStore = InMemoryIncomingPaymentSecretStore()
        secretStore.fetchError = InMemoryIncomingPaymentSecretStore.Failure()
        let service = makeService(store: store, secretStore: secretStore)

        await #expect {
            try await service.accept(
                amount: 50,
                descriptor: .coins(secretKeys: [Data([0x05])]),
                paymentId: "p2",
                productId: "prod"
            )
        } throws: { Self.isUnknown($0) }
        #expect(store.payment(for: "top up:prod:p2") == nil)
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

        let stream = try await service.subscribeStatus(for: "p1", productId: "prod")
        var observed: IncomingPaymentStatus?
        for try await status in stream {
            observed = status
            break
        }
        #expect(observed == .claimedPartially(actualClaimed: 42))
    }

    @Test func coldSubscribeToUnknownPaymentThrowsNotFound() async throws {
        let store = InMemoryIncomingPaymentStore()
        let service = makeService(store: store)

        await #expect {
            _ = try await service.subscribeStatus(for: "ghost", productId: "prod")
        } throws: { ($0 as? IncomingPaymentError) == .notFound("ghost") }
    }

    @Test(.timeLimit(.minutes(1)))
    func partialOutcomeIsAcknowledgedAndPersisted() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(
            detections: [.claiming, .claimedPartially(claimed: 40)],
            acknowledger: acknowledger
        )

        rig.service.setup(with: Self.denomination)
        try await waitUntil { acknowledger.calls().count == 1 }
        rig.service.throttle()

        let call = try #require(acknowledger.calls().first)
        #expect(call.outcome == .claimedPartially(actualClaimed: 40))
        #expect(call.requestedAmount == 100)
        #expect(rig.store.payment(for: "top up:prod:p")?.outcome == .claimedPartially(actualClaimed: 40))
    }

    @Test(.timeLimit(.minutes(1)))
    func notClaimedOutcomeIsAcknowledged() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(detections: [.notClaimed], acknowledger: acknowledger)

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.store.payment(for: "top up:prod:p")?.outcome == .notClaimed }
        rig.service.throttle()

        #expect(acknowledger.calls().map(\.outcome) == [.notClaimed])
    }

    @Test(.timeLimit(.minutes(1)))
    func claimedOutcomeIsNotAcknowledged() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(
            detections: [.claimed(amount: 100, finalized: true)],
            acknowledger: acknowledger
        )

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.store.payment(for: "top up:prod:p")?.outcome == .claimed }
        rig.service.throttle()

        #expect(acknowledger.calls().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func settleWipesSourceSecret() async throws {
        let rig = makeDrivingService(detections: [.notClaimed])

        #expect(rig.secretStore.hasDescriptor(for: "top up:prod:p"))

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.store.payment(for: "top up:prod:p")?.outcome == .notClaimed }
        rig.service.throttle()

        #expect(!rig.secretStore.hasDescriptor(for: "top up:prod:p"))
        #expect(rig.secretStore.removedGroupIds() == ["top up:prod:p"])
    }

    @Test(.timeLimit(.minutes(1)))
    func unreadableSecretLeavesPaymentActive() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(detections: [.notClaimed], acknowledger: acknowledger)
        rig.secretStore.fetchError = InMemoryIncomingPaymentSecretStore.Failure()

        rig.service.setup(with: Self.denomination)
        try await Task.sleep(for: .milliseconds(200))
        rig.service.throttle()

        #expect(rig.store.payment(for: "top up:prod:p")?.outcome == nil)
        #expect(rig.store.settledGroupIds().isEmpty)
        #expect(acknowledger.calls().isEmpty)
        #expect(rig.secretStore.removedGroupIds().isEmpty)
        #expect(rig.verdictResolver.askedGroupIds().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func lostSecretSettlesFromDurabilityGroup() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(
            detections: [.claimed(amount: 100, finalized: true)],
            acknowledger: acknowledger,
            secretPresent: false,
            durabilityVerdict: .success(.claimedPartially(claimed: 40))
        )

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.store.payment(for: "top up:prod:p")?.outcome != nil }
        rig.service.throttle()

        #expect(rig.verdictResolver.askedGroupIds() == ["top up:prod:p"])
        #expect(rig.claim.retryUntil() == nil)
        #expect(rig.store.payment(for: "top up:prod:p")?.outcome == .claimedPartially(actualClaimed: 40))
        #expect(acknowledger.calls().map(\.outcome) == [.claimedPartially(actualClaimed: 40)])
    }

    @Test(.timeLimit(.minutes(1)))
    func lostSecretWithUnobservableGroupLeavesPaymentActive() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(
            detections: [.notClaimed],
            acknowledger: acknowledger,
            secretPresent: false,
            durabilityVerdict: .failure(StubGroupVerdictResolver.Unobservable())
        )

        rig.service.setup(with: Self.denomination)
        try await waitUntil { !rig.verdictResolver.askedGroupIds().isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        rig.service.throttle()

        #expect(rig.store.payment(for: "top up:prod:p")?.outcome == nil)
        #expect(acknowledger.calls().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func unpersistedVerdictKeepsSecretAndDoesNotAcknowledge() async throws {
        let acknowledger = StubAcknowledger()
        let rig = makeDrivingService(detections: [.notClaimed], acknowledger: acknowledger)
        rig.store.settleError = InMemoryIncomingPaymentStore.Failure()

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.claim.retryUntil() != nil }
        try await Task.sleep(for: .milliseconds(200))
        rig.service.throttle()

        #expect(rig.store.payment(for: "top up:prod:p")?.outcome == nil)
        #expect(rig.secretStore.hasDescriptor(for: "top up:prod:p"))
        #expect(rig.secretStore.removedGroupIds().isEmpty)
        #expect(acknowledger.calls().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func claimRetryWindowIsTheOperationsOwn() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let rig = makeDrivingService(detections: [.notClaimed], createdAt: createdAt)

        rig.service.setup(with: Self.denomination)
        try await waitUntil { rig.claim.retryUntil() != nil }
        rig.service.throttle()

        let retryUntil = try #require(rig.claim.retryUntil())
        #expect(retryUntil == createdAt.addingTimeInterval(CoinageConstants.topUpRetryWindow))
    }

    struct DrivingRig {
        let service: IncomingPaymentService
        let store: InMemoryIncomingPaymentStore
        let secretStore: InMemoryIncomingPaymentSecretStore
        let claim: StubClaimCoinsService
        let verdictResolver: StubGroupVerdictResolver
        let payment: IncomingPayment
    }

    /// A service wired to drive one seeded `(prod, p)` payment (coins source) through a canned detection
    /// sequence to settlement. Without a secret the durability fallback answers `durabilityVerdict`.
    private func makeDrivingService(
        detections: [CoinageTransferDetection],
        acknowledger: StubAcknowledger = StubAcknowledger(),
        createdAt: Date = Date(),
        secretPresent: Bool = true,
        durabilityVerdict: Result<CoinageTransferDetection, Error> = .success(.notClaimed)
    ) -> DrivingRig {
        let payment = IncomingPayment(
            paymentId: "p",
            productId: "prod",
            amount: 100,
            createdAt: createdAt,
            outcome: nil
        )
        let store = InMemoryIncomingPaymentStore(seed: [payment])
        let secretStore = InMemoryIncomingPaymentSecretStore(
            seed: secretPresent ? ["top up:prod:p": .coins(secretKeys: [Data([0x01])])] : [:]
        )
        let claim = StubClaimCoinsService(detections: detections)
        let verdictResolver =
            switch durabilityVerdict {
            case let .success(verdict): StubGroupVerdictResolver(verdict: verdict)
            case let .failure(error): StubGroupVerdictResolver(error: error)
            }
        let service = IncomingPaymentService(
            store: store,
            secretStore: secretStore,
            sourceResolver: StubSourceResolver(),
            paymentContext: IncomingPaymentContext(logger: StubLogger()),
            claimCoinsService: claim,
            claimAssetService: StubClaimAssetService(),
            verdictResolver: verdictResolver,
            acknowledger: acknowledger,
            instanceId: 0,
            logger: StubLogger()
        )
        return DrivingRig(
            service: service,
            store: store,
            secretStore: secretStore,
            claim: claim,
            verdictResolver: verdictResolver,
            payment: payment
        )
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: Duration = .seconds(100)
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
