import Foundation
import Operation_iOS
import SubstrateSdk
import StructuredConcurrency
import AsyncExtensions
import AsyncAlgorithms
import BigInt
import SDKLogger

/// Legacy two-bucket spendable model, kept while stage-2 UI migrates to ``CoinagePrivacyBalance``.
/// `fullPrivacy` maps to the new `spendable` bucket, `degraded` to `gainingPrivacy`.
public struct CoinageSpendableBalanceModel: Equatable {
    public let fullPrivacy: CoinageBalance
    public let degraded: CoinageBalance

    public func totalInPlanks() -> Balance {
        fullPrivacy.balanceInPlanks() + degraded.balanceInPlanks()
    }

    public init(fullPrivacy: CoinageBalance, degraded: CoinageBalance) {
        self.fullPrivacy = fullPrivacy
        self.degraded = degraded
    }
}

/// The strategy-aware balance: what is spendable now, what is deliberately held back gaining privacy
/// (optionally spendable behind a confirmation), and what is still arriving or chain-forced.
public struct CoinagePrivacyBalance: Equatable {
    public let spendable: Balance
    public let gainingPrivacy: GainingPrivacy
    public let pending: Balance

    public struct GainingPrivacy: Equatable {
        public let amount: Balance
        public let canSpendWithConfirmation: Bool

        public init(amount: Balance, canSpendWithConfirmation: Bool) {
            self.amount = amount
            self.canSpendWithConfirmation = canSpendWithConfirmation
        }
    }

    public init(spendable: Balance, gainingPrivacy: GainingPrivacy, pending: Balance) {
        self.spendable = spendable
        self.gainingPrivacy = gainingPrivacy
        self.pending = pending
    }

    /// Spendable including gaining-privacy funds when the strategy allows confirmed spends.
    public var available: Balance {
        gainingPrivacy.canSpendWithConfirmation ? spendable + gainingPrivacy.amount : spendable
    }

    public var total: Balance {
        spendable + gainingPrivacy.amount + pending
    }
}

public protocol CoinageBalanceServiceProtocol {
    func start()
    func stop()

    var spendableBalanceStream: AnyAsyncSequence<CoinageSpendableBalanceModel> { get }
    var lockedBalanceStream: AnyAsyncSequence<CoinageBalance> { get }
    var privacyBalanceStream: AnyAsyncSequence<CoinagePrivacyBalance> { get }
}

public extension CoinageBalanceServiceProtocol {
    var totalBalanceStream: AnyAsyncSequence<CoinageBalance> {
        combineLatest(spendableBalanceStream, lockedBalanceStream)
            .map { spendable, locked in
                let planks = spendable.fullPrivacy.balanceInPlanks()
                    + spendable.degraded.balanceInPlanks()
                    + locked.balanceInPlanks()
                return CoinageBalance(planks: planks, context: locked.context)
            }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}

/// Buckets a full snapshot of tracked assets into the strategy-aware three-bucket balance, applying
/// the recycling evaluator's coin verdicts and the current strategy's voucher usability. Balance runs
/// the pre-classifiers itself on every emission (real-time) and takes only the coin verdicts from the
/// evaluator, so a spend drops the displayed balance immediately rather than up to an interval later.
public actor CoinageBalanceService: CoinageBalanceServiceProtocol {
    private nonisolated let denominationContext: DenominationBreakdownContext
    private nonisolated let databaseFactory: any DatabaseDependencyFactoring
    private nonisolated let verdicts: AnyAsyncSequence<RecyclingVerdicts>
    private nonisolated let settings: any CoinageRecyclingStrategyProviding
    private let strategyResolver: any RecyclingStrategyProviding
    private let ringCapacityProvider: any RingCapacityProviding
    private let preClassificator: any CoinageAssetsPreClassificating
    private nonisolated let logger: SDKLoggerProtocol?

    private var balanceSubscriptionTask: Task<Void, Never>?
    private var unlockTimerTask: Task<Void, Never>?

    private var latestCoins: [TrackedCoin] = []
    private var latestVouchers: [TrackedVoucher] = []
    private var latestVerdicts: RecyclingVerdicts = [:]

    private nonisolated let spendableBalanceSubject: AsyncCurrentValueSubject<CoinageSpendableBalanceModel>
    private nonisolated let lockedBalanceSubject: AsyncCurrentValueSubject<CoinageBalance>
    private nonisolated let privacyBalanceSubject: AsyncCurrentValueSubject<CoinagePrivacyBalance>

    init(
        denominationContext: DenominationBreakdownContext,
        databaseFactory: any DatabaseDependencyFactoring,
        verdicts: AnyAsyncSequence<RecyclingVerdicts>,
        settings: any CoinageRecyclingStrategyProviding,
        strategyResolver: any RecyclingStrategyProviding,
        ringCapacityProvider: any RingCapacityProviding,
        preClassificator: any CoinageAssetsPreClassificating,
        logger: SDKLoggerProtocol?
    ) {
        self.denominationContext = denominationContext
        self.databaseFactory = databaseFactory
        self.verdicts = verdicts
        self.settings = settings
        self.strategyResolver = strategyResolver
        self.ringCapacityProvider = ringCapacityProvider
        self.preClassificator = preClassificator
        self.logger = logger

        let zeroBalance = CoinageBalance(planks: 0, context: denominationContext)
        spendableBalanceSubject = AsyncCurrentValueSubject<CoinageSpendableBalanceModel>(
            CoinageSpendableBalanceModel(fullPrivacy: zeroBalance, degraded: zeroBalance)
        )
        lockedBalanceSubject = AsyncCurrentValueSubject<CoinageBalance>(zeroBalance)
        privacyBalanceSubject = AsyncCurrentValueSubject<CoinagePrivacyBalance>(
            CoinagePrivacyBalance(
                spendable: 0,
                gainingPrivacy: .init(amount: 0, canSpendWithConfirmation: false),
                pending: 0
            )
        )
    }

    public nonisolated var spendableBalanceStream: AnyAsyncSequence<CoinageSpendableBalanceModel> {
        spendableBalanceSubject.eraseToAnyAsyncSequence()
    }

    public nonisolated var lockedBalanceStream: AnyAsyncSequence<CoinageBalance> {
        lockedBalanceSubject.eraseToAnyAsyncSequence()
    }

    public nonisolated var privacyBalanceStream: AnyAsyncSequence<CoinagePrivacyBalance> {
        privacyBalanceSubject.eraseToAnyAsyncSequence()
    }

    public nonisolated func start() {
        Task { [weak self] in
            await self?.subscribeToBalances()
        }
    }

    public nonisolated func stop() {
        Task { [weak self] in
            await self?.cancelTasks()
        }
    }
}

private extension CoinageBalanceService {
    func subscribeToBalances() {
        balanceSubscriptionTask?.cancel()
        balanceSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            let coinsStream = databaseFactory.makeTrackedCoinSnapshotStream()
            let vouchersStream = databaseFactory.makeTrackedVoucherSnapshotStream()
            // Combining with `verdicts` withholds the first emission until the evaluator produces one,
            // so balance never flashes zero-available before the first evaluation lands.
            let combined = combineLatest(
                combineLatest(coinsStream, vouchersStream),
                verdicts,
                settings.strategyStream()
            )
            do {
                for try await ((coins, vouchers), verdictMap, type) in combined {
                    await update(coins: coins, vouchers: vouchers, verdicts: verdictMap, type: type)
                }
            } catch {
                logger?.error("Balance subscription failed: \(error)")
            }
        }
    }

    func update(
        coins: [TrackedCoin],
        vouchers: [TrackedVoucher],
        verdicts: RecyclingVerdicts,
        type _: RecyclingStrategyType
    ) async {
        latestCoins = coins
        latestVouchers = vouchers
        latestVerdicts = verdicts
        await recompute()
    }

    func cancelTasks() {
        balanceSubscriptionTask?.cancel()
        unlockTimerTask?.cancel()
    }

    func recompute() async {
        let now = Date()
        let voucherStrategy = strategyResolver.voucherStrategy(for: settings.strategy)

        let exponents = Set(latestVouchers.map(\.voucher.exponent))
        let capacities = await getCapacities(for: exponents)
        let usability = VoucherUsabilityContext(ringCapacities: capacities, now: now)

        let coinBuckets = preClassificator.preClassifyCoins(latestCoins)
        let voucherBuckets = preClassificator.preClassifyVouchers(
            latestVouchers,
            strategy: voucherStrategy,
            context: usability
        )

        var spendableCoins = BigUInt.zero
        var gainingCoins = BigUInt.zero
        var pendingCoins = BigUInt.zero
        for tracked in coinBuckets.minted {
            let amount = denominationContext.valueInPlanks(for: tracked.coin.exponent)
            switch latestVerdicts[tracked.coin.derivationIndex] {
            case .allowUse:
                spendableCoins += amount
            case .toRecycle:
                gainingCoins += amount
            case .mustRecycle,
                 .none:
                // Chain-forced, or not yet evaluated — both count as pending, never spendable.
                pendingCoins += amount
            }
        }

        let spendable = spendableCoins + voucherBuckets.usable.totalPlanks(in: denominationContext)
        let gainingAmount = gainingCoins + voucherBuckets.gainingPrivacy.totalPlanks(in: denominationContext)
        let pending = pendingCoins
            + coinBuckets.minting.totalPlanks(in: denominationContext)
            + voucherBuckets.minting.totalPlanks(in: denominationContext)

        publish(
            spendable: spendable,
            gainingAmount: gainingAmount,
            pending: pending,
            canSpendWithConfirmation: voucherStrategy.allowsConfirmedSpend()
        )

        scheduleUnlockTimer(for: nextUnlock(among: voucherBuckets.gainingPrivacy, now: now))
    }

    func getCapacities(for exponents: Set<Int16>) async -> [Int16: Int] {
        do {
            return try await ringCapacityProvider.capacities(for: exponents)
        } catch {
            logger?.error("Failed to get capacities: \(error)")
            return [:]
        }
    }

    func publish(spendable: Balance, gainingAmount: Balance, pending: Balance, canSpendWithConfirmation: Bool) {
        privacyBalanceSubject.send(
            CoinagePrivacyBalance(
                spendable: spendable,
                gainingPrivacy: .init(amount: gainingAmount, canSpendWithConfirmation: canSpendWithConfirmation),
                pending: pending
            )
        )

        // Compatibility mapping for the legacy streams until stage-2 migrates consumers.
        spendableBalanceSubject.send(
            CoinageSpendableBalanceModel(
                fullPrivacy: CoinageBalance(planks: spendable, context: denominationContext),
                degraded: CoinageBalance(planks: gainingAmount, context: denominationContext)
            )
        )
        lockedBalanceSubject.send(CoinageBalance(planks: pending, context: denominationContext))
    }

    /// The earliest future `readyAt` among gaining-privacy vouchers, so the delay-exit is re-evaluated
    /// the moment a voucher's unload delay elapses.
    func nextUnlock(among gainingPrivacy: [TrackedVoucher], now: Date) -> Date? {
        gainingPrivacy
            .map(\.voucher.readyAt)
            .filter { $0 > now }
            .min()
    }

    func scheduleUnlockTimer(for nextUnlock: Date?) {
        unlockTimerTask?.cancel()
        guard let nextUnlock else { return }

        let interval = nextUnlock.timeIntervalSince(.now)
        guard interval > 0 else { return }

        unlockTimerTask = Task { [weak self] in
            // Add 0.1s buffer so `.now` has passed the target when the task wakes.
            try? await Task.sleep(for: .seconds(interval + 0.1))
            guard !Task.isCancelled, let self else { return }
            await recompute()
        }
    }
}
