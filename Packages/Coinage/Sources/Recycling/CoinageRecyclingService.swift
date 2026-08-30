import Foundation
import ExtrinsicService
import KeyDerivation
import Keystore_iOS
import Operation_iOS
import SDKLogger
import SubstrateSdk
import StructuredConcurrency

/// Persisted recycling intent handed from `prepareRecycle` to the submission step.
private struct PreparedRecycle {
    let voucher: Voucher
    let origin: any ExtrinsicOriginDefining
    let builder: ExtrinsicBuilderClosure
}

/// Schedules and executes coin recycling to prevent expiration.
/// Fire-and-forget submits each eligible coin; the durability layer resolves the outcome.
actor CoinageRecyclingService {
    private let coinService: CoinServiceProtocol
    private let voucherMinter: any VoucherMinting
    private let coinKeypairFactory: any CoinKeyDeriving
    private let voucherKeypairFactory: any VoucherKeyDeriving
    private let durability: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol

    private let schedulerFactory: CoinRecycleSchedulerMaking
    private let backgroundRecyclingInterval: TimeInterval
    private let recycleAtAge: Int16

    init(
        schedulerFactory: CoinRecycleSchedulerMaking,
        coinService: CoinServiceProtocol,
        voucherMinter: any VoucherMinting,
        coinKeypairFactory: any CoinKeyDeriving,
        voucherKeypairFactory: any VoucherKeyDeriving,
        durability: any CoinageTxServicing,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol,
        backgroundRecyclingInterval: TimeInterval,
        recycleAtAge: Int16
    ) {
        self.schedulerFactory = schedulerFactory
        self.coinService = coinService
        self.voucherMinter = voucherMinter
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
            try await recycleCoin(coin)
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

            var submittedCount = 0
            var failedCount = 0

            for coin in eligibleCoins {
                if Task.isCancelled { break }

                do {
                    try await recycleCoin(coin)
                    submittedCount += 1
                } catch {
                    logger.error("Recycle failed for coin \(coin.derivationIndex), leaving for recovery: \(error)")
                    failedCount += 1
                }
            }

            logger.debug("Recycling run complete: \(submittedCount) submitted, \(failedCount) failed")
        } catch {
            logger.error("Recycling run failed: \(error)")
        }
    }

    /// Fire-and-forget recycle of a single coin, matching Appendix B's `load_recycler_with_coin`:
    /// `prepareRecycle` mints the voucher, then `submit` registers the entry —
    /// which claims the coin — and tracks the extrinsic in the background. The durability layer
    /// resolves the outcome; a coin whose extrinsic never lands is released by the recovery pass at
    /// mortality, so there is nothing to roll back here.
    func recycleCoin(_ coin: Coin) async throws {
        let prepared = try await prepareRecycle(coin)
        try await durability.submitTransaction(
            request: CoinageTxRequest(
                inputs: [.coin(.own(coin.derivationIndex, coin.publicKey))],
                outputs: [.recyclerVoucher(prepared.voucher.derivationIndex, prepared.voucher.publicKey)],
                builder: prepared.builder,
                origin: prepared.origin
            ),
            groupId: nil
        )
        logger.debug("Submitted recycle: coin \(coin.derivationIndex) -> voucher \(prepared.voucher.derivationIndex)")
    }

    /// Locks the coin, allocates the voucher, and persists the voucher (`.pendingOnboarding`)
    /// before submission so a crash mid-flight is recoverable. Throws before anything is broadcast.
    func prepareRecycle(_ coin: Coin) async throws -> PreparedRecycle {
        // The coin is reserved by its `load_recycler` durability entry at submission — a live
        // input derives to `.pendingTransfer` — so no separate pre-lock is written here.
        let voucher = try await voucherMinter.mintVoucher(exponent: coin.exponent)

        let memberKey = voucher.publicKey
        let keyManager = try voucherKeypairFactory.createKeyManager(for: voucher)
        let coinPublicKey = coin.publicKey
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

        // The voucher is already persisted by the allocator, so a crash mid-flight is recoverable.
        return PreparedRecycle(voucher: voucher, origin: origin, builder: builder)
    }

    func fetchEligibleCoins() async throws -> [Coin] {
        try await coinService.fetchAllTrackedCoins()
            .filter { $0.isAwaitingRecycling(for: recycleAtAge) }
            .map(\.coin)
            .sorted { ($0.age ?? 0) > ($1.age ?? 0) }
    }
}
