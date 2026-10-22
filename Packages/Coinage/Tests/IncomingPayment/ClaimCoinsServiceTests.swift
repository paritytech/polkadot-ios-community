import Testing
import AsyncExtensions
import Foundation
import NovaCrypto
import os
import StructuredConcurrencyTestSupport
@testable import Coinage

@Suite(.timeLimit(.minutes(5)))
struct ClaimCoinsServiceTests {
    private static let detectionTimeout: Duration = .seconds(30)
    private static let resubscribeDelay: Duration = .seconds(1)

    private static let denomination = DenominationBreakdownContext(
        unit: 1,
        precision: 0,
        maxExponent: 3,
        minExponent: 0
    )

    @Test
    func passWithoutLookPastWindowKeepsWaiting() async throws {
        let rig = try Rig(windowFromNow: -1)
        let run = rig.start()

        for _ in 0 ..< 3 {
            await rig.clock.resumeSleep(for: Self.detectionTimeout)
        }
        await rig.clock.waitForSleep(for: Self.detectionTimeout)

        #expect(!run.isFinished)
        #expect(rig.submitter.submittedPublicKeys.isEmpty)
        run.cancel()
    }

    @Test
    func firstLookPastWindowIsClaimedThenWindowCloses() async throws {
        let rig = try Rig(windowFromNow: -1)
        let run = rig.start()

        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        // A second pass proves the silent one past the window did not end the claim.
        await rig.clock.waitForSleep(for: Self.detectionTimeout)
        await rig.query.waitForSubscriptions(1)
        rig.query.send([rig.coinPublicKey: Self.coinInfo])
        await rig.submitter.waitForSubmissions(1)

        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        let detections = await run.detections()

        #expect(rig.submitter.submittedPublicKeys == [[rig.coinPublicKey]])
        #expect(detections.last == .notClaimed)
    }

    @Test
    func lookInsideWindowLetsLaterSilentPassClose() async throws {
        let rig = try Rig(windowFromNow: 60)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        rig.query.send([rig.coinPublicKey: Self.coinInfo])
        await rig.submitter.waitForSubmissions(1)

        await rig.clock.waitForSleep(for: Self.detectionTimeout)
        rig.moveNow(by: 120)
        await rig.clock.resumeSleep(for: Self.detectionTimeout)

        #expect(await run.detections().last == .notClaimed)
    }

    @Test
    func failedSubscriptionIsReopened() async throws {
        let rig = try Rig(windowFromNow: -1)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        rig.query.fail()
        await rig.clock.resumeSleep(for: Self.resubscribeDelay)
        await rig.query.waitForSubscriptions(2)
        rig.query.send([rig.coinPublicKey: Self.coinInfo])
        await rig.submitter.waitForSubmissions(1)

        #expect(rig.submitter.submittedPublicKeys == [[rig.coinPublicKey]])
        run.cancel()
    }

    @Test
    func emptyLookInsideWindowKeepsPolling() async throws {
        let rig = try Rig(windowFromNow: 60)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        rig.query.send([:])
        for _ in 0 ..< 3 {
            await rig.clock.resumeSleep(for: Self.detectionTimeout)
        }
        await rig.clock.waitForSleep(for: Self.detectionTimeout)

        #expect(!run.isFinished)
        run.cancel()
    }

    @Test
    func silentPassIsNotAbsent() async throws {
        let rig = try Rig(windowFromNow: 60)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        await rig.clock.waitForSleep(for: Self.detectionTimeout)
        run.cancel()

        #expect(await !(run.detections()).contains(.absent))
    }

    @Test
    func emptyLookWithNothingClaimedIsAbsentOnceAndNeverDetectingAfter() async throws {
        let rig = try Rig(windowFromNow: 60)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        rig.query.send([:])
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        await rig.clock.waitForSleep(for: Self.detectionTimeout)
        rig.moveNow(by: 120)
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        let detections = await run.detections()

        let firstAbsent = try #require(detections.firstIndex(of: .absent))
        #expect(detections.filter { $0 == .absent }.count == 1)
        #expect(!detections[firstAbsent...].contains(.detecting))
        #expect(detections.last == .notClaimed)
    }

    @Test
    func absentGivesWayToDetectingWhenCoinsAppear() async throws {
        let rig = try Rig(windowFromNow: 60)
        let run = rig.start()

        await rig.query.waitForSubscriptions(1)
        rig.query.send([:])
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        await rig.clock.waitForSleep(for: Self.detectionTimeout)
        rig.query.send([rig.coinPublicKey: Self.coinInfo])
        await rig.submitter.waitForSubmissions(1)
        rig.moveNow(by: 120)
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        let detections = await run.detections()

        let firstAbsent = try #require(detections.firstIndex(of: .absent))
        #expect(detections[firstAbsent...].contains(.detecting))
        #expect(detections.last == .notClaimed)
    }

    @Test
    func noAbsentWhileWeAlreadyHoldAClaim() async throws {
        let rig = try Rig(windowFromNow: -1)
        rig.txService.seedClaim("claim-coins-test", receivedPublicKey: rig.siblingPublicKey, status: .finalizedSuccess)
        let run = rig.start(coinKeys: [rig.coinSecret, rig.siblingSecret])

        await rig.query.waitForSubscriptions(1)
        rig.query.send([:])
        await rig.clock.resumeSleep(for: Self.detectionTimeout)
        let detections = await run.detections()

        #expect(!detections.contains(.absent))
        #expect(detections.last == .claimedPartially(claimed: 0))
    }
}

private extension ClaimCoinsServiceTests {
    static let coinInfo = ClaimableCoinInfo(exponent: 0, age: 0)

    /// One claim of a single coin against a scripted chain, on a manual clock and a movable date.
    struct Rig {
        let clock: ManualClock
        let query: ScriptedCoinInfoQuery
        let submitter: RecordingClaimSubmitter
        let coinSecret: Data
        let coinPublicKey: Data
        let siblingSecret: Data
        let siblingPublicKey: Data
        let txService: StubGroupTxService
        let retryUntil: Date

        private let dateProvider: MovableDateProvider
        private let service: ClaimCoinsService

        init(windowFromNow: TimeInterval) throws {
            let keyFactory = SNKeyFactory()
            let keypair = try keyFactory.createKeypair(fromSeed: Data(repeating: 0xAB, count: 32))
            let sibling = try keyFactory.createKeypair(fromSeed: Data(repeating: 0xCD, count: 32))
            let start = Date()
            let dateProvider = MovableDateProvider(now: start)
            let clock = ManualClock()
            let query = ScriptedCoinInfoQuery()
            let submitter = RecordingClaimSubmitter()
            let txService = StubGroupTxService()

            service = ClaimCoinsService(
                txService: txService,
                coinOnChainQuery: query,
                claimSubmitter: submitter,
                snKeyFactory: keyFactory,
                coinService: StubCoinService(),
                timing: ClaimCoinsService.Timing(
                    detectionTimeout: ClaimCoinsServiceTests.detectionTimeout,
                    resubscribeDelay: ClaimCoinsServiceTests.resubscribeDelay,
                    clock: clock,
                    dateProvider: dateProvider
                ),
                logger: StubLogger()
            )
            self.clock = clock
            self.query = query
            self.submitter = submitter
            self.dateProvider = dateProvider
            self.txService = txService
            coinSecret = keypair.privateKey().rawData()
            coinPublicKey = keypair.publicKey().rawData()
            siblingSecret = sibling.privateKey().rawData()
            siblingPublicKey = sibling.publicKey().rawData()
            retryUntil = start.addingTimeInterval(windowFromNow)
        }

        func start(coinKeys: [Data]? = nil) -> ClaimRun {
            ClaimRun(stream: service.claim(
                coinKeys: coinKeys ?? [coinSecret],
                groupId: "claim-coins-test",
                retryUntil: retryUntil,
                context: ClaimCoinsServiceTests.denomination
            ))
        }

        func moveNow(by interval: TimeInterval) {
            dateProvider.advance(by: interval)
        }
    }

    /// A claim in flight: collects its detections and says whether the stream has finished.
    final class ClaimRun: @unchecked Sendable {
        private let task: Task<[CoinageTransferDetection], Never>
        private let finished = OSAllocatedUnfairLock(initialState: false)

        init(stream: AnyAsyncSequence<CoinageTransferDetection>) {
            let finished = finished
            task = Task {
                var detections: [CoinageTransferDetection] = []
                do {
                    for try await detection in stream {
                        detections.append(detection)
                    }
                } catch {}
                finished.withLock { $0 = true }
                return detections
            }
        }

        var isFinished: Bool { finished.withLock { $0 } }

        func detections() async -> [CoinageTransferDetection] { await task.value }

        func cancel() { task.cancel() }
    }
}
