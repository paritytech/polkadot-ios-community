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
    let walEntry: TransferWALEntry
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
    private let coordinator: ExtrinsicSubmissionCoordinating
    private let walStore: any TransferWALStoring
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol

    private let schedulerFactory: CoinRecycleSchedulerMaking
    private let backgroundRecyclingInterval: TimeInterval
    private let mortality: UInt32
    private let recycleAtAge: Int16

    init(
        schedulerFactory: CoinRecycleSchedulerMaking,
        coinService: CoinServiceProtocol,
        voucherAllocator: any VoucherAllocating,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        coinKeypairFactory: any CoinKeyDeriving,
        voucherKeypairFactory: any VoucherKeyDeriving,
        coordinator: ExtrinsicSubmissionCoordinating,
        walStore: any TransferWALStoring,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol,
        backgroundRecyclingInterval: TimeInterval,
        mortality: UInt32,
        recycleAtAge: Int16
    ) {
        self.schedulerFactory = schedulerFactory
        self.coinService = coinService
        self.voucherAllocator = voucherAllocator
        self.voucherRepository = voucherRepository
        self.coinKeypairFactory = coinKeypairFactory
        self.voucherKeypairFactory = voucherKeypairFactory
        self.coordinator = coordinator
        self.walStore = walStore
        self.originFactory = originFactory
        self.logger = logger
        self.backgroundRecyclingInterval = backgroundRecyclingInterval
        self.mortality = mortality
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

    /// Executes the full recycling flow for a single coin, durable across crashes via the WAL:
    /// 1. `prepareRecycle` locks the coin, allocates the voucher, and persists voucher + WAL before submitting
    /// 2. Submit `load_recycler_with_coin` through the WAL-aware coordinator (captures the checkpoint block)
    /// 3. `resolveSubmission` commits the on-chain outcome and clears the WAL
    ///
    /// A pre-submission error reverts the coin. A thrown submission leaves the WAL entry + `.recycling`
    /// state for startup recovery to resolve against the chain.
    func recycleCoin(_ coin: Coin) async -> CoinRecycleResult {
        let prepared: PreparedRecycle
        do {
            prepared = try await prepareRecycle(coin)
        } catch {
            logger.error("Pre-submission error for coin \(coin.derivationIndex): \(error)")
            try? await coinService.markAvailable(coinIds: [coin.identifier])
            return .failed(error)
        }

        do {
            let submission = try await coordinator.submit(
                walEntryId: prepared.walEntry.id,
                builder: prepared.builder,
                origin: prepared.origin
            )
            return try await resolveSubmission(submission, coin: coin, prepared: prepared)
        } catch {
            logger.error("Submission error for coin \(coin.derivationIndex), leaving for recovery: \(error)")
            return .failed(error)
        }
    }

    /// Locks the coin, allocates the voucher, and persists the voucher (`.pendingOnboarding`) + WAL entry
    /// before submission so a crash mid-flight is recoverable. Throws before anything is broadcast.
    func prepareRecycle(_ coin: Coin) async throws -> PreparedRecycle {
        // Lock the coin first: a crash at any later point leaves a recoverable `.recycling` coin.
        try await coinService.markRecycling(coinIds: [coin.identifier])

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

        // Persist the voucher and WAL before submission so a crash mid-flight is recoverable.
        try await voucherRepository.saveOperation(
            { [voucher] },
            { [] }
        ).asyncExecute()

        let walEntry = TransferWALEntry(
            operationType: .recycleIntoVoucher,
            inputCoinIds: [coin.identifier],
            expectedVoucherIndices: [voucher.derivationIndex],
            mortality: mortality
        )
        try await walStore.save(walEntry)

        return PreparedRecycle(voucher: voucher, walEntry: walEntry, origin: origin, builder: builder)
    }

    /// Commits the on-chain outcome and clears the WAL: success keeps the voucher and spends the coin,
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
            try await coinService.markSpent(coinIds: [coin.identifier])
            try await walStore.delete(id: prepared.walEntry.id)
            logger.debug("Recycled coin \(coin.derivationIndex) -> voucher \(prepared.voucher.derivationIndex)")
            return .recycled(prepared.voucher)

        case let .failure(error):
            logger.warning("Coin \(coin.derivationIndex) destroyed on-chain: \(error)")
            try await coinService.markSpent(coinIds: [coin.identifier])
            try await voucherRepository.saveOperation(
                { [] },
                { [prepared.voucher.identifier] }
            ).asyncExecute()
            try await walStore.delete(id: prepared.walEntry.id)

            return .destroyed
        }
    }

    func fetchEligibleCoins() async throws -> [Coin] {
        try await coinService.fetchAllCoins()
            .filter { coin in
                guard let age = coin.age else { return false }

                return coin.state == .available && age >= recycleAtAge
            }
            .sorted { ($0.age ?? 0) > ($1.age ?? 0) }
    }
}
