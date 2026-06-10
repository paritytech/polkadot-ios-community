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

/// Schedules and executes coin recycling to prevent expiration.
/// Processes eligible coins sequentially with three-way error handling per coin.
actor CoinageRecyclingService {
    private static let scheduledDateKey = "io.coinage.recycler.scheduledDate"

    private let coinService: CoinServiceProtocol
    private let voucherAllocator: any VoucherAllocating
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let coinKeypairFactory: any CoinKeyDeriving
    private let voucherKeypairFactory: any VoucherKeyDeriving
    private let extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol
    private let originFactory: OriginCreating
    private let connection: JSONRPCEngine
    private let logger: SDKLoggerProtocol
    private let settingsManager: SettingsManagerProtocol

    private let schedulerFactory: CoinRecycleSchedulerMaking
    private let recyclingInterval: TimeInterval
    private let recycleAtAge: Int16

    init(
        schedulerFactory: CoinRecycleSchedulerMaking,
        settingsManager: SettingsManagerProtocol,
        coinService: CoinServiceProtocol,
        voucherAllocator: any VoucherAllocating,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        coinKeypairFactory: any CoinKeyDeriving,
        voucherKeypairFactory: any VoucherKeyDeriving,
        extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        originFactory: OriginCreating,
        connection: JSONRPCEngine,
        logger: SDKLoggerProtocol,
        recyclingInterval: TimeInterval,
        recycleAtAge: Int16
    ) {
        self.schedulerFactory = schedulerFactory
        self.settingsManager = settingsManager
        self.coinService = coinService
        self.voucherAllocator = voucherAllocator
        self.voucherRepository = voucherRepository
        self.coinKeypairFactory = coinKeypairFactory
        self.voucherKeypairFactory = voucherKeypairFactory
        self.extrinsicMonitorFactory = extrinsicMonitorFactory
        self.originFactory = originFactory
        self.connection = connection
        self.logger = logger
        self.recyclingInterval = recyclingInterval
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

    func scheduleRecycling() async {
        guard let scheduledTimestamp = settingsManager.double(for: Self.scheduledDateKey) else {
            logger.debug("No scheduled recycling task found, scheduling new one")
            await scheduleTask()
            return
        }

        guard Date(timeIntervalSince1970: scheduledTimestamp) <= .now else {
            logger.debug("Recycling task already scheduled, skipping")
            return
        }

        logger.debug("Recycle now and schedule next")

        await runRecycling()
        await scheduleTask()
    }
}

// MARK: - Private

private extension CoinageRecyclingService {
    func scheduleTask() async {
        let plannedDate = Date(timeIntervalSinceNow: recyclingInterval)
        settingsManager.set(value: plannedDate.timeIntervalSince1970, for: Self.scheduledDateKey)

        await schedulerFactory
            .makeScheduler()
            .schedule(earliestBegin: recyclingInterval)
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

    /// Executes the full recycling flow for a single coin:
    /// 1. Lock coin as .recycling
    /// 2. Allocate voucher and derive keys
    /// 3. Build and submit load_recycler_with_coin extrinsic
    /// 4. Handle three-way result: success, post-inclusion failure, pre-submission error
    func recycleCoin(_ coin: Coin) async -> CoinRecycleResult {
        do {
            // Lock coin as .recycling before extrinsic submission
            try await coinService.markRecycling(coinIds: [coin.identifier])

            // Allocate voucher and derive keys
            let voucher = try await voucherAllocator.allocate(exponent: coin.exponent)
            let memberKey = try voucherKeypairFactory.derivePublicKey(for: voucher)
            let keyManager = try voucherKeypairFactory.createKeyManager(for: voucher)
            let coinPublicKey = try coinKeypairFactory.derivePublicKey(for: coin)
            let proof = try keyManager.sign(coinPublicKey)

            // Build call and origin
            let call = CoinagePallet.Calls.LoadRecyclerWithCoin(
                memberKey: memberKey,
                proofOfOwnership: proof
            )
            let coinWallet = try CoinDerivedWallet(
                privateKey: coinKeypairFactory.derivePrivateKey(for: coin),
                publicKey: coinPublicKey
            )
            let origin = try originFactory.createAsCoinOrigin(for: coinWallet)

            let builder: ExtrinsicBuilderClosure = {
                try $0.adding(call: call.callAsFunction())
            }

            // Submit and monitor
            let result = try await extrinsicMonitorFactory.submitAndMonitorWrapper(
                extrinsicBuilderClosure: builder,
                origin: origin,
                params: .empty
            ).asyncExecute()

            // Handle result
            switch result.status {
            case .success:
                try? await voucherRepository.saveOperation({ [voucher] }, { [] }).asyncExecute()
                try? await coinService.markSpent(coinIds: [coin.identifier])
                logger.debug("Recycled coin \(coin.derivationIndex) -> voucher \(voucher.derivationIndex)")
                return .recycled(voucher)

            case let .failure(error):
                logger.warning("Coin \(coin.derivationIndex) destroyed on-chain: \(error)")
                try? await coinService.markSpent(coinIds: [coin.identifier])
                return .destroyed
            }
        } catch {
            // TODO: We still might have a corner case when connection failed but an extrinsic reached the node
            // Pre-submission error: coin safe, revert to .available
            logger.error("Pre-submission error for coin \(coin.derivationIndex): \(error)")
            try? await coinService.markAvailable(coinIds: [coin.identifier])
            return .failed(error)
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
