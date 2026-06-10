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
    private nonisolated let voucherProvider: StreamableProvider<Voucher>
    private nonisolated let coinProvider: StreamableProvider<Coin>
    private nonisolated let logger: SDKLoggerProtocol?

    private var balanceSubscriptionTask: Task<Void, Never>?
    private var unlockTimerTask: Task<Void, Never>?

    private var latestCoins: [String: Coin] = [:]
    private var latestVouchers: [String: Voucher] = [:]

    private nonisolated let spendableBalanceSubject: AsyncCurrentValueSubject<CoinageSpendableBalanceModel>
    private nonisolated let lockedBalanceSubject: AsyncCurrentValueSubject<CoinageBalance>

    init(
        denominationContext: DenominationBreakdownContext,
        voucherProvider: StreamableProvider<Voucher>,
        coinProvider: StreamableProvider<Coin>,
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
                    .scan([String: Coin]()) { dict, changes in
                        changes.mergeToDict(dict)
                    }

                let vouchersStream = voucherProvider.asyncStream()
                    .scan([String: Voucher]()) { dict, changes in
                        changes.mergeToDict(dict)
                    }

                for try await (coins, vouchers) in combineLatest(coinsStream, vouchersStream) {
                    await updateBalances(coins: coins, vouchers: vouchers)
                }
            } catch {
                logger?.error("Balance subscription failed: \(error)")
            }
        }
    }

    private func cancelTasks() {
        balanceSubscriptionTask?.cancel()
        unlockTimerTask?.cancel()
    }

    private func updateBalances(coins: [String: Coin]?, vouchers: [String: Voucher]?) {
        if let coins { latestCoins = coins }
        if let vouchers { latestVouchers = vouchers }

        let currentCoins = latestCoins
        let currentVouchers = latestVouchers
        logger?.debug("Did receive coins: \(currentCoins.count) vouchers: \(currentVouchers.count)")

        let (spendableBalance, lockedBalance, nextUnlock) = calculateBalance(
            coins: currentCoins,
            vouchers: currentVouchers,
            context: denominationContext
        )

        spendableBalanceSubject.send(spendableBalance)
        lockedBalanceSubject.send(lockedBalance)

        scheduleUnlockTimer(for: nextUnlock)
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
            await updateBalances(coins: nil, vouchers: nil)
        }
    }

    private nonisolated func calculateBalance(
        coins: [String: Coin],
        vouchers: [String: Voucher],
        context: DenominationBreakdownContext
    ) -> (spendable: CoinageSpendableBalanceModel, locked: CoinageBalance, nextUnlock: Date?) {
        let now = Date.now

        let coinsPlanks = coins.values
            .filter { $0.state == .available }
            .map { context.valueInPlanks(for: $0.exponent) }
            .reduce(BigUInt(0), +)

        let recyclingCoinsPlanks = coins.values
            .filter { $0.state == .recycling }
            .map { context.valueInPlanks(for: $0.exponent) }
            .reduce(BigUInt(0), +)

        var lockedVouchersPlanks = BigUInt(0)
        var fullPrivacyVouchersPlanks = BigUInt(0)
        var degradedVouchersPlanks = BigUInt(0)
        var nextUnlock: Date?

        for voucher in vouchers.values where voucher.localState == .available {
            let amount = context.valueInPlanks(for: voucher.exponent)

            guard case .inRecycler = voucher.remoteState else {
                lockedVouchersPlanks += amount
                continue
            }

            if voucher.effectivePrivacy(at: now) == .full {
                fullPrivacyVouchersPlanks += amount
            } else {
                degradedVouchersPlanks += amount
                // Track when this voucher becomes full-privacy due to readyAt passing
                if voucher.readyAt > now, voucher.privacy == .full {
                    nextUnlock = min(nextUnlock ?? voucher.readyAt, voucher.readyAt)
                }
            }
        }

        let lockedPlanks = lockedVouchersPlanks + recyclingCoinsPlanks

        return (
            spendable: CoinageSpendableBalanceModel(
                fullPrivacy: CoinageBalance(planks: coinsPlanks + fullPrivacyVouchersPlanks, context: context),
                degraded: CoinageBalance(planks: degradedVouchersPlanks, context: context)
            ),
            locked: CoinageBalance(planks: lockedPlanks, context: context),
            nextUnlock: nextUnlock
        )
    }
}
