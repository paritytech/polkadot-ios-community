import Foundation
import AsyncExtensions
import AsyncAlgorithms
import Operation_iOS
import SubstrateSdk
import SDKLogger

/// Derives coin recycling verdicts on a throttled cadence and triggers recycling for gated coins.
///
/// The verdict depends on the current balance ratio and on the ages of every other active coin, both
/// of which move, so it is computed, never persisted. Balance consumes ``verdicts`` (deduplicated);
/// the recycle trigger fires from the evaluation body, not from a verdict observer, so an unchanged
/// verdict after a failed recycle still retries.
public actor CoinRecyclingEvaluator {
    private nonisolated let databaseFactory: any DatabaseDependencyFactoring
    private nonisolated let settings: any CoinageRecyclingStrategyProviding
    private let strategyProvider: any RecyclingStrategyProviding
    private let ringCapacityProvider: any RingCapacityProviding
    private let preClassificator: any CoinageAssetsPreClassificating
    private let recyclingService: any CoinageRecyclingServicing
    private let quotaTracker: any UnloadQuotaTracking
    private nonisolated let denominationContext: DenominationBreakdownContext
    private nonisolated let logger: SDKLoggerProtocol?

    /// Nil until the first evaluation completes — balance must not emit before it, or it reads as zero.
    private nonisolated let verdictsSubject = AsyncCurrentValueSubject<RecyclingVerdicts?>(nil)

    private var latestCoins: [TrackedCoin] = []
    private var latestVouchers: [TrackedVoucher] = []
    private var latestType: RecyclingStrategyType

    private var assetsTask: Task<Void, Never>?
    private var strategyTask: Task<Void, Never>?

    private static let evaluationInterval: Duration = .seconds(5)

    init(
        databaseFactory: any DatabaseDependencyFactoring,
        settings: any CoinageRecyclingStrategyProviding,
        strategyProvider: any RecyclingStrategyProviding,
        ringCapacityProvider: any RingCapacityProviding,
        preClassificator: any CoinageAssetsPreClassificating,
        recyclingService: any CoinageRecyclingServicing,
        quotaTracker: any UnloadQuotaTracking,
        denominationContext: DenominationBreakdownContext,
        logger: SDKLoggerProtocol?
    ) {
        self.databaseFactory = databaseFactory
        self.settings = settings
        self.strategyProvider = strategyProvider
        self.ringCapacityProvider = ringCapacityProvider
        self.preClassificator = preClassificator
        self.recyclingService = recyclingService
        self.quotaTracker = quotaTracker
        self.denominationContext = denominationContext
        self.logger = logger
        latestType = settings.strategy
    }

    /// Verdicts stream — deduplicated and withheld until the first evaluation lands.
    public nonisolated var verdicts: AnyAsyncSequence<RecyclingVerdicts> {
        verdictsSubject.compactMap { $0 }.eraseToAnyAsyncSequence()
    }

    public nonisolated func start() {
        Task { [weak self] in await self?.run() }
    }

    public nonisolated func stop() {
        Task { [weak self] in await self?.cancelTasks() }
    }
}

private extension CoinRecyclingEvaluator {
    func run() {
        let coinsStream = databaseFactory.makeTrackedCoinSnapshotStream()
        let vouchersStream = databaseFactory.makeTrackedVoucherSnapshotStream()

        // A leading tick (immediate) followed by a periodic one, folded into the throttled asset path.
        // The tick is load-bearing twice: it arms balanced's delay exit without an external event, and
        // it re-emits every interval as the retry path now that the worker is gone.
        let leadingTick: AsyncSyncSequence<[Void]> = [()].async
        let tick = chain(
            leadingTick,
            AsyncTimerSequence(interval: Self.evaluationInterval, clock: ContinuousClock()).map { _ in () }
        )

        // Assets + tick are throttled: the voucher pass, capacity lookup, quota read and gating walk
        // run at most once per interval however bursty the ledger writes are.
        assetsTask = Task { [weak self] in
            let data = combineLatest(coinsStream, vouchersStream)
            let throttled = combineLatest(data, tick)._throttle(for: Self.evaluationInterval, latest: true)
            do {
                for try await ((coins, vouchers), _) in throttled {
                    await self?.updateAssets(coins: coins, vouchers: vouchers)
                }
            } catch {
                self?.logger?.error("Recycling evaluator asset stream failed: \(error)")
            }
        }

        // Strategy changes re-judge immediately, outside the throttle: flipping the privacy switch must
        // re-evaluate the whole active set now, not up to an interval later.
        strategyTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await type in settings.strategyStream() {
                    await updateStrategy(type)
                }
            } catch {
                logger?.error("Recycling evaluator strategy stream failed: \(error)")
            }
        }
    }

    func cancelTasks() {
        assetsTask?.cancel()
        strategyTask?.cancel()
    }

    func updateAssets(coins: [TrackedCoin], vouchers: [TrackedVoucher]) async {
        latestCoins = coins
        latestVouchers = vouchers
        await evaluateAndRecycle()
    }

    func updateStrategy(_ type: RecyclingStrategyType) async {
        latestType = type
        await evaluateAndRecycle()
    }

    func evaluateAndRecycle() async {
        do {
            let verdicts = try await evaluate(
                now: Date(),
                coins: latestCoins,
                vouchers: latestVouchers,
                type: latestType
            )
            verdictsSubject.send(verdicts)
            await recycleGated(verdicts, coins: latestCoins)
        } catch {
            logger?.error("Recycling evaluation failed: \(error)")
        }
    }

    func evaluate(
        now: Date,
        coins: [TrackedCoin],
        vouchers: [TrackedVoucher],
        type: RecyclingStrategyType
    ) async throws -> RecyclingVerdicts {
        let voucherExponents = Set(vouchers.map(\.voucher.exponent))
        let capacities = try await ringCapacityProvider.capacities(for: voucherExponents)
        let usabilityContext = VoucherUsabilityContext(ringCapacities: capacities, now: now)

        let coinBuckets = preClassificator.preClassifyCoins(coins)
        let voucherBuckets = preClassificator.preClassifyVouchers(
            vouchers,
            strategy: strategyProvider.voucherStrategy(for: type),
            context: usabilityContext
        )

        let snapshot = RecyclingSnapshot(
            total: coinBuckets.all.totalPlanks(in: denominationContext)
                + voucherBuckets.all.totalPlanks(in: denominationContext),
            unavailable: coinBuckets.minting.totalPlanks(in: denominationContext)
                + voucherBuckets.minting.totalPlanks(in: denominationContext)
                + voucherBuckets.gainingPrivacy.totalPlanks(in: denominationContext)
        )

        let coinStrategy = try await strategyProvider.coinStrategy(for: type)
        return coinStrategy.evaluate(
            coins: coinBuckets.minted.map(\.coin),
            snapshot: snapshot,
            context: denominationContext
        )
    }

    func recycleGated(_ verdicts: RecyclingVerdicts, coins: [TrackedCoin]) async {
        let gated = Set(verdicts.filter(\.value.triggersRecycling).keys)
        guard !gated.isEmpty else { return }

        // `recycleCoins` skips coins whose ledger state is not free, so the 5s cadence is idempotent.
        let coinsToRecycle = coins.filter { gated.contains($0.coin.derivationIndex) }.map(\.coin)
        do {
            try await recyclingService.recycleCoins(coinsToRecycle)
            await quotaTracker.noteUnloadHappened()
        } catch {
            logger?.error("Recycle trigger failed: \(error)")
        }
    }
}
