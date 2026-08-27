import Foundation
import Operation_iOS
import SubstrateSdk
import StructuredConcurrency
import AsyncExtensions
import AsyncAlgorithms
import BigInt
import SDKLogger

public struct CoinageSpendableBalanceModel: Equatable {
    /// Coins and in-recycler vouchers with full effective privacy.
    public let fullPrivacy: CoinageBalance
    /// In-recycler vouchers with degraded effective privacy (not time-ready or low ring size).
    public let degraded: CoinageBalance

    public func totalInPlanks() -> Balance {
        fullPrivacy.balanceInPlanks() + degraded.balanceInPlanks()
    }

    public init(fullPrivacy: CoinageBalance, degraded: CoinageBalance) {
        self.fullPrivacy = fullPrivacy
        self.degraded = degraded
    }
}

public protocol CoinageBalanceServiceProtocol {
    func start()
    func stop()

    var spendableBalanceStream: AnyAsyncSequence<CoinageSpendableBalanceModel> { get }
    var lockedBalanceStream: AnyAsyncSequence<CoinageBalance> { get }
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

public actor CoinageBalanceService: CoinageBalanceServiceProtocol {
    enum ServiceError: Error {
        case assetNotFound
    }

    private nonisolated let denominationContext: DenominationBreakdownContext
    private nonisolated let voucherProvider: StreamableProvider<TrackedVoucher>
    private nonisolated let coinProvider: StreamableProvider<TrackedCoin>
    private nonisolated let logger: SDKLoggerProtocol?

    private var balanceSubscriptionTask: Task<Void, Never>?
    private var unlockTimerTask: Task<Void, Never>?

    private var latestCoins: [String: TrackedCoin] = [:]
    private var latestVouchers: [String: TrackedVoucher] = [:]

    private nonisolated let spendableBalanceSubject: AsyncCurrentValueSubject<CoinageSpendableBalanceModel>
    private nonisolated let lockedBalanceSubject: AsyncCurrentValueSubject<CoinageBalance>

    init(
        denominationContext: DenominationBreakdownContext,
        voucherProvider: StreamableProvider<TrackedVoucher>,
        coinProvider: StreamableProvider<TrackedCoin>,
        logger: SDKLoggerProtocol?
    ) {
        self.denominationContext = denominationContext
        self.voucherProvider = voucherProvider
        self.coinProvider = coinProvider
        self.logger = logger

        let zeroBalance = CoinageBalance(planks: 0, context: denominationContext)
        spendableBalanceSubject = AsyncCurrentValueSubject<CoinageSpendableBalanceModel>(
            CoinageSpendableBalanceModel(fullPrivacy: zeroBalance, degraded: zeroBalance)
        )
        lockedBalanceSubject = AsyncCurrentValueSubject<CoinageBalance>(zeroBalance)
    }

    public nonisolated var spendableBalanceStream: AnyAsyncSequence<CoinageSpendableBalanceModel> {
        spendableBalanceSubject.eraseToAnyAsyncSequence()
    }

    public nonisolated var lockedBalanceStream: AnyAsyncSequence<CoinageBalance> {
        lockedBalanceSubject.eraseToAnyAsyncSequence()
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

extension CoinageBalanceService {
    private func subscribeToBalances() {
        balanceSubscriptionTask?.cancel()
        balanceSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                logger?.debug("Balance subscription started")
                // Providers produce changes
                // and we need to collect them to have full info
                let coinsStream = coinProvider.asyncStream()
                    .scan([String: TrackedCoin]()) { dict, changes in
                        changes.mergeToDict(dict)
                    }

                let vouchersStream = voucherProvider.asyncStream()
                    .scan([String: TrackedVoucher]()) { dict, changes in
                        changes.mergeToDict(dict)
                    }

                for try await (coins, vouchers) in combineLatest(coinsStream, vouchersStream) {
                    await updateBalancesAsync(coins: coins, vouchers: vouchers)
                }
            } catch {
                logger?.error("Balance subscription failed: \(error)")
            }
        }
    }

    private func updateBalancesAsync(coins: [String: TrackedCoin]?, vouchers: [String: TrackedVoucher]?) async {
        if let coins { latestCoins = coins }
        if let vouchers { latestVouchers = vouchers }

        let currentCoins = latestCoins
        let currentVouchers = latestVouchers
        logger?.debug("Did receive coins: \(currentCoins.count) vouchers: \(currentVouchers.count)")

        // Each tracked asset already carries its durability overlay (`CoinageAssetState`), derived
        // at fetch time — no separate batched durability read is needed here.
        let (spendableBalance, lockedBalance, nextUnlock) = calculateBalance(
            coins: currentCoins,
            vouchers: currentVouchers,
            context: denominationContext
        )

        spendableBalanceSubject.send(spendableBalance)
        lockedBalanceSubject.send(lockedBalance)

        scheduleUnlockTimer(for: nextUnlock)
    }

    private func cancelTasks() {
        balanceSubscriptionTask?.cancel()
        unlockTimerTask?.cancel()
    }

    private func scheduleUnlockTimer(for nextUnlock: Date?) {
        unlockTimerTask?.cancel()
        guard let nextUnlock else { return }

        let interval = nextUnlock.timeIntervalSince(.now)
        guard interval > 0 else { return }

        unlockTimerTask = Task { [weak self] in
            // Add 0.1s buffer to guarantee `.now` will have passed the target date
            // when the task wakes up, avoiding a race condition.
            try? await Task.sleep(for: .seconds(interval + 0.1))

            guard !Task.isCancelled, let self else { return }
            await updateBalancesAsync(coins: nil, vouchers: nil)
        }
    }

    private nonisolated func calculateBalance(
        coins: [String: TrackedCoin],
        vouchers: [String: TrackedVoucher],
        context: DenominationBreakdownContext
    ) -> (spendable: CoinageSpendableBalanceModel, locked: CoinageBalance, nextUnlock: Date?) {
        let now = Date.now

        let coinPlanks = splitCoinPlanks(coins: coins.values, context: context)

        var lockedVouchersPlanks = BigUInt(0)
        var fullPrivacyVouchersPlanks = BigUInt(0)
        var degradedVouchersPlanks = BigUInt(0)
        var nextUnlock: Date?

        for tracked in vouchers.values {
            let voucher = tracked.voucher
            let amount = context.valueInPlanks(for: voucher.exponent)

            if tracked.isSelectable {
                // In the recycler on chain — spendable; on-chain presence is authoritative even if a
                // local minting entry is still live. Split by effective privacy.
                if voucher.isReadyToUseSecured(at: now) {
                    fullPrivacyVouchersPlanks += amount
                } else {
                    degradedVouchersPlanks += amount
                    // Track when this voucher becomes full-privacy due to readyAt passing
                    if voucher.readyAt > now, voucher.privacy == .full {
                        nextUnlock = min(nextUnlock ?? voucher.readyAt, voucher.readyAt)
                    }
                }
            } else if tracked.isOnboarding || tracked.isMinting {
                // Not usable yet but expected to arrive: locked until it lands in the recycler.
                lockedVouchersPlanks += amount
            }
            // Otherwise (reserved by a live entry, or a dead/orphan voucher): counted nowhere.
        }

        let lockedPlanks = lockedVouchersPlanks + coinPlanks.expiringSoon + coinPlanks.pending

        return (
            spendable: CoinageSpendableBalanceModel(
                fullPrivacy: CoinageBalance(planks: coinPlanks.spendable + fullPrivacyVouchersPlanks, context: context),
                degraded: CoinageBalance(planks: degradedVouchersPlanks, context: context)
            ),
            locked: CoinageBalance(planks: lockedPlanks, context: context),
            nextUnlock: nextUnlock
        )
    }

    /// Buckets coins by the durability overlay carried on each `TrackedCoin`. Every disposition is a
    /// named predicate; a coin matching none (not free, or dead/vanished) is counted nowhere.
    ///
    /// | Predicate | Bucket |
    /// |---|---|
    /// | ``TrackedCoin/isSelectable`` — free, on chain, age-valid | spendable |
    /// | ``TrackedCoin/isMinting`` — not on chain yet, minter still live | pending (locked) |
    /// | ``TrackedCoin/isAwaitingRecycling`` — on chain, free, aged out | expiringSoon (locked) |
    private nonisolated func splitCoinPlanks(
        coins: some Collection<TrackedCoin>,
        context: DenominationBreakdownContext
    ) -> (spendable: BigUInt, pending: BigUInt, expiringSoon: BigUInt) {
        var spendable = BigUInt(0)
        var pending = BigUInt(0)
        var expiringSoon = BigUInt(0)

        for tracked in coins {
            let amount = context.valueInPlanks(for: tracked.coin.exponent)

            if tracked.isSelectable {
                spendable += amount
            } else if tracked.isMinting {
                pending += amount
            } else if tracked.isAwaitingRecycling {
                expiringSoon += amount
            }
        }

        return (spendable, pending, expiringSoon)
    }
}
