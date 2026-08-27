import Foundation
import ExtrinsicService
import KeyDerivation
import Keystore_iOS
import Operation_iOS
import SDKLogger
import SubstrateSdk
import StructuredConcurrency

/// Outcome of a single coin recycling attempt.
enum CoinRecycleResult {
    /// Coin successfully recycled into a new voucher.
    case recycled(Voucher)
    /// Post-submission failure: coin used on-chain but no voucher created.
    case destroyed
    /// Pre-submission failure: coin reverted to .available, safe to retry.
    case failed(Error)
}

/// Persisted recycling intent handed from `prepareRecycle` to the submission step.
private struct PreparedRecycle {
    let voucher: Voucher
    let origin: any ExtrinsicOriginDefining
    let builder: ExtrinsicBuilderClosure
}

/// Schedules and executes coin recycling to prevent expiration.
/// Processes eligible coins sequentially with three-way error handling per coin.
actor CoinageRecyclingService {
    private let coinService: CoinServiceProtocol
    private let voucherAllocator: any VoucherAllocating
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let coinKeypairFactory: any CoinKeyDeriving
    private let voucherKeypairFactory: any VoucherKeyDeriving
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol

    private let schedulerFactory: CoinRecycleSchedulerMaking
    private let backgroundRecyclingInterval: TimeInterval
    private let recycleAtAge: Int16

    init(
        schedulerFactory: CoinRecycleSchedulerMaking,
        coinService: CoinServiceProtocol,
        voucherAllocator: any VoucherAllocating,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        coinKeypairFactory: any CoinKeyDeriving,
        voucherKeypairFactory: any VoucherKeyDeriving,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol,
        backgroundRecyclingInterval: TimeInterval,
        recycleAtAge: Int16
    ) {
        self.schedulerFactory = schedulerFactory
        self.coinService = coinService
        self.voucherAllocator = voucherAllocator
        self.voucherRepository = voucherRepository
        self.coinKeypairFactory = coinKeypairFactory
        self.voucherKeypairFactory = voucherKeypairFactory
        self.durability = durability
        self.originFactory = originFactory
        self.logger = logger
        self.backgroundRecyclingInterval = backgroundRecyclingInterval
        self.recycleAtAge = recycleAtAge
    }
}

// MARK: - CoinageRecyclingServicing

extension CoinageRecyclingService: CoinageRecyclingServicing {
    func recycleCoins(_ coins: [Coin]) async throws {
        for coin in coins {
            let result = await recycleCoin(coin)
            if case let .failed(error) = result {
                throw error
            }
        }
    }

    func recycleOldCoins() async {
        await runRecycling()
    }

    func scheduleRecycling() async {
        await ensureScheduled()
        await runRecycling()
    }
}

// MARK: - Private

private extension CoinageRecyclingService {
    func ensureScheduled() async {
        await schedulerFactory
            .makeScheduler()
            .schedule(earliestBegin: backgroundRecyclingInterval)
    }

    func runRecycling() async {
        logger.debug("Starting recycling run")

        do {
            let eligibleCoins = try await fetchEligibleCoins()

            guard !eligibleCoins.isEmpty else {
                logger.debug("No eligible coins for recycling")
                return
            }

            logger.debug("Found \(eligibleCoins.count) eligible coins for recycling")

            var recycledCount = 0
            var destroyedCount = 0
            var failedCount = 0

            for coin in eligibleCoins {
                if Task.isCancelled { break }

                let result = await recycleCoin(coin)
                switch result {
                case .recycled: recycledCount += 1
                case .destroyed: destroyedCount += 1
                case .failed: failedCount += 1
                }
            }

            logger.debug(
                "Recycling run complete: \(recycledCount) recycled, \(destroyedCount) destroyed, \(failedCount) failed"
            )
        } catch {
            logger.error("Recycling run failed: \(error)")
        }
    }

    /// Executes the full recycling flow for a single coin, durable across crashes via the durability engine:
    /// A recycle consumes one coin and mints one voucher, matching Appendix B's `load_recycler_with_coin`.
    /// 1. `prepareRecycle` locks the coin, allocates the voucher, and persists voucher before submitting
    /// 2. Submit `load_recycler_with_coin` through the durability engine (captures the checkpoint block)
    /// 3. `resolveSubmission` commits the on-chain outcome
    ///
    /// A pre-submission error reverts the coin. A thrown submission is recoverable by startup recovery.
    func recycleCoin(_ coin: Coin) async -> CoinRecycleResult {
        let prepared: PreparedRecycle
        do {
            prepared = try await prepareRecycle(coin)
        } catch {
            logger.error("Pre-submission error for coin \(coin.derivationIndex): \(error)")
            return .failed(error)
        }

        do {
            let result = try await durability.submit(
                inputs: [.coin(.own(coin.derivationIndex))],
                outputs: [.recyclerVoucher(prepared.voucher.derivationIndex)],
                builder: prepared.builder,
                origin: prepared.origin
            )
            return try await resolveSubmission(result.submission, coin: coin, prepared: prepared)
        } catch {
            logger.error("Submission error for coin \(coin.derivationIndex), leaving for recovery: \(error)")
            return .failed(error)
        }
    }

    /// Locks the coin, allocates the voucher, and persists the voucher (`.pendingOnboarding`)
    /// before submission so a crash mid-flight is recoverable. Throws before anything is broadcast.
    func prepareRecycle(_ coin: Coin) async throws -> PreparedRecycle {
        // The coin is reserved by its `load_recycler` durability entry at submission — a live
        // input derives to `.pendingTransfer` — so no separate pre-lock is written here.
        let voucher = try await voucherAllocator
            .allocate(exponent: coin.exponent)
            .withLocalState(.pendingOnboarding)

        let memberKey = try voucherKeypairFactory.derivePublicKey(for: voucher)
        let keyManager = try voucherKeypairFactory.createKeyManager(for: voucher)
        let coinPublicKey = try coinKeypairFactory.derivePublicKey(for: coin)
        let proof = try keyManager.sign(coinPublicKey)

        let call = CoinagePallet.Calls.LoadRecyclerWithCoin(
            memberKey: memberKey,
            proofOfOwnership: proof
        )
        let coinWallet = try CoinDerivedWallet(
            privateKey: coinKeypairFactory.derivePrivateKey(for: coin),
            publicKey: coinPublicKey
        )
        let origin = try originFactory.createAsCoinOrigin(for: coinWallet)
        let builder: ExtrinsicBuilderClosure = { try $0.adding(call: call.callAsFunction()) }

        // Persist the voucher before submission so a crash mid-flight is recoverable.
        try await voucherRepository.saveOperation(
            { [voucher.withLocalState(.pendingOnboarding)] },
            { [] }
        ).asyncExecute()

        return PreparedRecycle(voucher: voucher, origin: origin, builder: builder)
    }

    /// Commits the on-chain outcome: success keeps the voucher and spends the coin,
    /// on-chain failure drops the voucher and spends the coin.
    func resolveSubmission(
        _ submission: ExtrinsicMonitorSubmission,
        coin: Coin,
        prepared: PreparedRecycle
    ) async throws -> CoinRecycleResult {
        switch submission.status {
        case .success:
            try await voucherRepository
                .saveOperation(
                    { [prepared.voucher.withLocalState(.available)] },
                    { [] }
                ).asyncExecute()
            try await coinService.save(coins: [coin.changing(isOnchain: false)])
            logger.debug("Recycled coin \(coin.derivationIndex) -> voucher \(prepared.voucher.derivationIndex)")
            return .recycled(prepared.voucher)

        case let .failure(error):
            logger.warning("Coin \(coin.derivationIndex) destroyed on-chain: \(error)")
            try await coinService.save(coins: [coin.changing(isOnchain: false)])
            try await voucherRepository.saveOperation(
                { [] },
                { [prepared.voucher.identifier] }
            ).asyncExecute()

            return .destroyed
        }
    }

    func fetchEligibleCoins() async throws -> [Coin] {
        try await coinService.fetchAllTrackedCoins()
            .filter { $0.isAwaitingRecycling(for: recycleAtAge) }
            .map(\.coin)
            .sorted { ($0.age ?? 0) > ($1.age ?? 0) }
    }
}
