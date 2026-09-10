import Testing
import Foundation
import KeyDerivation
import SubstrateSdk
@testable import Coinage

/// Drives `ClaimAssetService` against a fake chain: a stub balance tracker, a loader that registers
/// real durability entries with `MockCoinageTxService`, and an in-memory voucher store to value them.
struct ClaimAssetServiceTests {
    /// Denominations 8, 4, 2, 1 planks.
    private static let denomination = DenominationBreakdownContext(
        unit: 1,
        precision: 0,
        maxExponent: 3,
        minExponent: 0
    )

    /// Denominations 8, 4, 2 planks — 1 plank can never be loaded.
    private static let coarseDenomination = DenominationBreakdownContext(
        unit: 1,
        precision: 0,
        maxExponent: 3,
        minExponent: 1
    )

    private static let fastTiming = ClaimAssetService.Timing(
        detectionTimeout: .milliseconds(50),
        resubscribeDelay: .milliseconds(10)
    )

    private static let wallet = DynamicDerivedWallet(
        derivationPath: "//topup",
        entropyManager: MockEntropyManager(entropy: Data(repeating: 0x02, count: 32))
    )

    @Test(.timeLimit(.minutes(1)))
    func exactAmountIsClaimedAndFinalized() async throws {
        let rig = makeRig(tracking: StubAssetsTracking(looks: [10]))

        let detections = try await rig.run(amount: 10, retryUntil: .distantFuture, context: Self.denomination)

        #expect(detections.first == .detecting)
        #expect(detections.contains(.claiming))
        #expect(detections.last == .claimed(amount: 10, finalized: true))
        #expect(rig.loader.loads() == [10])
    }

    @Test(.timeLimit(.minutes(1)))
    func remainderBelowSmallestDenominationEndsAsPartial() async throws {
        let rig = makeRig(tracking: StubAssetsTracking(looks: [11]))

        let detections = try await rig.run(
            amount: 11, retryUntil: Date().addingTimeInterval(0.3), context: Self.coarseDenomination
        )

        #expect(detections.last == .claimedPartially(claimed: 10))
        // The 1-plank remainder is not attempted again: nothing could ever load it.
        #expect(rig.loader.loads() == [11])
    }

    @Test(.timeLimit(.minutes(1)))
    func nothingArrivingWithinWindowIsNotClaimed() async throws {
        let tracking = StubAssetsTracking(looks: [])
        let rig = makeRig(tracking: tracking)

        let detections = try await rig.run(
            amount: 10,
            retryUntil: Date().addingTimeInterval(0.25),
            context: Self.denomination
        )

        #expect(detections.first == .detecting)
        #expect(!detections.contains(.claiming))
        #expect(detections.last == .notClaimed)
        #expect(rig.loader.loads().isEmpty)
        #expect(tracking.trackCalls() == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func closedWindowIsNotAttemptedEvenWhenFunded() async throws {
        let rig = makeRig(tracking: StubAssetsTracking(looks: [10]))

        let detections = try await rig.run(
            amount: 10,
            retryUntil: Date().addingTimeInterval(-1),
            context: Self.denomination
        )

        #expect(detections.first == .detecting)
        #expect(!detections.contains(.claiming))
        #expect(detections.last == .notClaimed)
        #expect(rig.loader.loads().isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func unopenableTrackerIsRetriedAtItsDelayUntilTheWindowCloses() async throws {
        let tracking = StubAssetsTracking(openError: StubAssetsTracking.Unavailable())
        let rig = makeRig(tracking: tracking)

        let detections = try await rig.run(
            amount: 10,
            retryUntil: Date().addingTimeInterval(0.25),
            context: Self.denomination
        )

        #expect(detections.last == .notClaimed)
        #expect(rig.loader.loads().isEmpty)
        // Reopened after each failure, paced by the resubscribe delay — never back to back.
        #expect((2 ... 60).contains(tracking.trackCalls()))
    }

    @Test(.timeLimit(.minutes(1)))
    func failingLoadIsRetriedAtDetectionCadenceUntilTheWindowCloses() async throws {
        let rig = makeRig(tracking: StubAssetsTracking(looks: [10]))
        rig.loader.loadError = StubVoucherLoaderFactory.Failure()

        let detections = try await rig.run(
            amount: 10,
            retryUntil: Date().addingTimeInterval(0.3),
            context: Self.denomination
        )

        #expect(detections.last == .notClaimed)
        #expect((1 ... 12).contains(rig.loader.loads().count))
    }

    @Test(.timeLimit(.minutes(1)))
    func batchFailingOnChainIsRetriedAtDetectionCadenceUntilTheWindowCloses() async throws {
        let rig = makeRig(tracking: StubAssetsTracking(looks: [10]), submissionOutcome: .chainFailure)

        let detections = try await rig.run(
            amount: 10,
            retryUntil: Date().addingTimeInterval(0.3),
            context: Self.denomination
        )

        #expect(detections.last == .notClaimed)
        #expect((2 ... 12).contains(rig.loader.loads().count))
    }

    @Test(.timeLimit(.minutes(1)))
    func fundsArrivingLaterAreClaimed() async throws {
        let tracking = StubAssetsTracking(looks: [0])
        let rig = makeRig(tracking: tracking)

        async let run = rig.run(amount: 10, retryUntil: .distantFuture, context: Self.denomination)
        try await Task.sleep(for: .milliseconds(120))
        tracking.send(10)

        let detections = try await run
        #expect(detections.last == .claimed(amount: 10, finalized: true))
        #expect(rig.loader.loads() == [10])
    }

    struct Rig {
        let service: ClaimAssetService
        let loader: StubVoucherLoaderFactory

        func run(
            amount: Balance,
            retryUntil: Date,
            context: DenominationBreakdownContext
        ) async throws -> [CoinageTransferDetection] {
            var detections: [CoinageTransferDetection] = []
            for try await detection in service.claim(
                wallet: ClaimAssetServiceTests.wallet,
                amount: amount,
                groupId: "top up:prod:p",
                retryUntil: retryUntil,
                instanceId: 0,
                context: context
            ) {
                detections.append(detection)
            }
            return detections
        }
    }

    private func makeRig(
        tracking: StubAssetsTracking,
        submissionOutcome: MockCoinageTxService.SubmissionOutcome = .success
    ) -> Rig {
        let txService = MockCoinageTxService(submissionOutcome: submissionOutcome)
        let vouchers = InMemoryVoucherService()
        let loader = StubVoucherLoaderFactory(vouchers: vouchers, txService: txService)
        let service = ClaimAssetService(
            assetsTracking: tracking,
            voucherLoaderFactory: loader,
            voucherService: vouchers,
            txService: txService,
            timing: Self.fastTiming,
            logger: StubLogger()
        )
        return Rig(service: service, loader: loader)
    }
}
