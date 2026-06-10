import Foundation
import BigInt
import FoundationExt
import KeyDerivation
import SubstrateSdk
import Operation_iOS
import AsyncExtensions
import SDKLogger
import StateMachine

/// Protocol defining the coinage facade operations.
public protocol CoinageServicing: Actor {
    /// The underlying recipient service for direct use.
    nonisolated var ongoingTransferService: any OngoingTransferServicing { get }

    nonisolated var transferRecoveryService: any TransferRecoveryServicing { get }

    /// The external payment service — exposed for dependency registration.
    /// Lifecycle (setup/throttle) is managed internally by CoinageService.
    nonisolated var externalPaymentService: any ExternalPaymentServicing { get }

    /// Suspends until the denomination context is ready, then returns it.
    /// Throws if `setup(with:)` has not been called or if setup failed.
    func denominationContext() async throws -> DenominationBreakdownContext

    /// Configure the facade with an asset. Must be called before other operations.
    /// - Parameter asset: The asset providing decimal precision
    /// - Throws: Errors from context loading
    func setup(with asset: AssetProtocol) async throws

    /// Load vouchers for a given amount, signed by the wallet that holds the external asset.
    /// Suspends and waits if the service has not been configured with an asset yet.
    /// - Parameters:
    ///   - amount: The fiat amount to load into vouchers
    ///   - externalAssetHolder: Wallet whose origin signs the on-chain extrinsic and whose
    ///     external asset is being onboarded into vouchers
    /// - Throws: CoinageError on failure
    func loadVouchers(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging
    ) async throws

    /// Provides a service to stream total and locked balance updates.
    /// Suspends and waits if the service has not been configured with an asset yet.
    func coinageBalanceService() async throws -> CoinageBalanceServiceProtocol

    /// Preview an external payment for UI validation (degraded privacy check).
    func previewExternalPayment(for amount: BigUInt) async throws -> ExternalPaymentPreview

    /// Initiate an external payment. Saves to store and returns the payment id.
    func initiateExternalPayment(
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws -> String

    /// Subscribe to the status of an external payment.
    func subscribeExternalPaymentStatus(
        paymentId: String
    ) throws -> AnyAsyncSequence<ExternalPaymentStatus>

    /// Preview a transfer and compute both the full and non-degraded sendable amounts.
    func previewTransfer(for amount: BigUInt) async throws -> TransferPreview

    /// Execute a transfer from a pre-computed coin selection result, skipping coin selection.
    func executeTransfer(result: CoinSelectionResult) async throws -> TransferMemo

    /// Scans the chain for coins and vouchers belonging to the user.
    /// Runs coin and voucher recovery concurrently.
    /// - Returns: Tuple of recovered coins and vouchers found on-chain
    /// - Throws: `CoinageError.notConfigured` if recovery service is unavailable
    func recoverCoinsAndVouchers() async throws -> (coins: ScanResult<Coin>, vouchers: ScanResult<Voucher>)

    /// See `TransferClaimServicing.transferCoinsFromSecretKeys`.
    func transferCoinsFromSecretKeys(
        secretKeys: [Data],
        transferCoins: Bool
    ) async throws -> BigUInt

    /// Scans beyond the given horizons for new coins and vouchers.
    /// Runs coin and voucher extend scan concurrently.
    /// Returns discovered items and updated horizons.
    func extendScanCoinsAndVouchers(
        coinHorizon: Int,
        voucherHorizon: Int
    ) async throws -> (coins: ScanResult<Coin>, vouchers: ScanResult<Voucher>)

    /// Recover spent coins by re-sweeping them back into the user's balance.
    /// Enumerates locally spent coins, derives their secret keys, and transfers them via
    /// `transferCoinsFromSecretKeys(transferCoins: true)`.
    /// - Returns: Total planks recovered and transferred
    /// - Throws: Errors from coin enumeration, key derivation, or transfer execution
    func recoverSpentCoinsOnChain() async throws -> BigUInt
}

/// Facade that coordinates transfer execution and balance queries across services.
public actor CoinageService {
    // Coins and vouchers management
    private let coinService: CoinServiceProtocol
    private let voucherService: VoucherServiceProtocol
    private let coinKeypairFactory: CoinKeyDeriving

    // Transfers
    private let senderService: TransferSenderServicing
    public nonisolated let ongoingTransferService: any OngoingTransferServicing
    public nonisolated let transferRecoveryService: any TransferRecoveryServicing

    // Sync services
    private let coinStateSyncService: CoinStateSyncService?
    private let voucherLocationService: VoucherLocationService?
    private let recoveryService: any CoinageBackupRecoveryServicing
    public nonisolated let recyclingService: any CoinageRecyclingServicing

    // External payment — lifecycle managed internally, exposed for dependency registration
    public nonisolated let externalPaymentService: any ExternalPaymentServicing

    private let contextLoader: DenominationContextLoaderProtocol

    // Balance observation
    private let coinProvider: StreamableProvider<Coin>
    private let voucherProvider: StreamableProvider<Voucher>
    private let logger: SDKLoggerProtocol?

    // App State
    private let applicationStateStreamFactory: ApplicationStateStreamFactory
    private var appStateTask: Task<Void, Never>?

    private var breakdownContext: DenominationBreakdownContext?
    private var cachedBalanceService: CoinageBalanceServiceProtocol?

    /// Cached task for the first context fetch. Concurrent callers await the same task;
    /// cancelled tasks propagate naturally without leaking continuations.
    /// Reset to nil on failure to allow retry via a subsequent `setup(with:)` call.
    private var contextSetupTask: Task<DenominationBreakdownContext, Error>?
    /// The asset associated with `contextSetupTask`. Used to detect asset changes
    /// while a fetch is in-flight so the task is replaced rather than reused.
    private var contextSetupAssetId: AssetId?
    /// Broadcasts context results to callers that arrived before setup() created contextSetupTask.
    /// nil = not yet set up; .success = ready; .failure = last setup failed (reset to nil on retry).
    private let contextSubject = AsyncCurrentValueSubject<Result<DenominationBreakdownContext, Error>?>(nil)

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        coinKeypairFactory: CoinKeyDeriving,
        senderService: TransferSenderServicing,
        ongoingTransferService: any OngoingTransferServicing,
        transferRecoveryService: any TransferRecoveryServicing,
        externalPaymentService: any ExternalPaymentServicing,
        contextLoader: DenominationContextLoaderProtocol,
        coinStateSyncService: CoinStateSyncService? = nil,
        voucherLocationService: VoucherLocationService? = nil,
        recyclingService: any CoinageRecyclingServicing,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        coinProvider: StreamableProvider<Coin>,
        voucherProvider: StreamableProvider<Voucher>,
        recoveryService: any CoinageBackupRecoveryServicing,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
        self.coinKeypairFactory = coinKeypairFactory
        self.senderService = senderService
        self.ongoingTransferService = ongoingTransferService
        self.externalPaymentService = externalPaymentService
        self.contextLoader = contextLoader
        self.coinStateSyncService = coinStateSyncService
        self.voucherLocationService = voucherLocationService
        self.recyclingService = recyclingService
        self.applicationStateStreamFactory = applicationStateStreamFactory
        self.coinProvider = coinProvider
        self.voucherProvider = voucherProvider
        self.recoveryService = recoveryService
        self.transferRecoveryService = transferRecoveryService
        self.logger = logger
    }
}

// MARK: - CoinageServicing

extension CoinageService: CoinageServicing {
    // MARK: External Payment Delegation

    public func previewExternalPayment(for amount: BigUInt) async throws -> ExternalPaymentPreview {
        let context = try await requireContext()
        return try await externalPaymentService.previewPayment(for: amount, context: context)
    }

    public func initiateExternalPayment(
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws -> String {
        try await externalPaymentService.initiatePayment(
            origin: origin,
            amountInPlanks: amountInPlanks,
            destination: destination
        )
    }

    public func subscribeExternalPaymentStatus(
        paymentId: String
    ) throws -> AnyAsyncSequence<ExternalPaymentStatus> {
        try externalPaymentService.subscribePaymentStatus(paymentId: paymentId)
    }

    // MARK: Denomination Context

    public func denominationContext() async throws -> DenominationBreakdownContext {
        try await requireContext()
    }

    public func setup(with asset: AssetProtocol) async throws {
        do {
            let context: DenominationBreakdownContext
            if let existing = breakdownContext {
                // Re-setup: update precision synchronously, no fetch needed
                context = existing.withChanging(asset: asset)
            } else {
                // First setup: create a shared task so concurrent callers
                // await the same fetch rather than each registering a continuation.
                let task: Task<DenominationBreakdownContext, Error>
                if let existing = contextSetupTask, contextSetupAssetId == asset.assetId {
                    task = existing
                } else {
                    // Reset subject so subject-path waiters from a prior failed attempt
                    // resume waiting rather than seeing a stale .failure result.
                    contextSubject.send(nil)
                    task = Task { [contextLoader] in try await contextLoader.fetchContext(for: asset) }
                    contextSetupTask = task
                    contextSetupAssetId = asset.assetId
                }
                let fetched = try await task.value
                // Guard against reentrancy: another setup call may have set breakdownContext
                // while we were suspended awaiting the task.
                guard breakdownContext == nil else { return }
                context = fetched
            }
            breakdownContext = context
            contextSubject.send(.success(context))

            // Start sync services
            coinStateSyncService?.setup()
            voucherLocationService?.setup()
            externalPaymentService.setup(with: context)

            subscribeForeground()

            Task { await recyclingService.scheduleRecycling() }
        } catch {
            // Reset so a subsequent setup(with:) call triggers a fresh fetch
            contextSetupTask = nil
            contextSetupAssetId = nil
            contextSubject.send(.failure(error))
            throw error
        }
    }

    // MARK: Coinage Transfers

    public func transferCoinsFromSecretKeys(
        secretKeys: [Data],
        transferCoins: Bool
    ) async throws -> BigUInt {
        let context = try await requireContext()
        return try await ongoingTransferService.transferCoinsFromSecretKeys(
            secretKeys: secretKeys,
            transferCoins: transferCoins,
            context: context
        )
    }

    public func previewTransfer(for amount: BigUInt) async throws -> TransferPreview {
        guard let denominationContext = breakdownContext else {
            throw CoinageError.notConfigured
        }

        let coins = try await coinService.fetchAllCoins()
        let vouchers = try await voucherService.fetchAvailableInRecycler()

        let result = try await senderService.previewStrategy(
            amount: amount,
            availableCoins: coins,
            availableVouchers: vouchers,
            breakdownContext: denominationContext
        )

        let nonDegradedAmount: BigUInt =
            if result.privacyLevel == .full {
                amount
            } else {
                computeNonDegradedAmount(from: result, context: denominationContext)
            }

        return TransferPreview(selectionResult: result, fullAmount: amount, nonDegradedAmount: nonDegradedAmount)
    }

    public func executeTransfer(result: CoinSelectionResult) async throws -> TransferMemo {
        guard let denominationContext = breakdownContext else {
            throw CoinageError.notConfigured
        }

        let transferContext = TransferContext(coinService: coinService, voucherService: voucherService)

        do {
            return try await senderService.execute(
                result: result,
                breakdownContext: denominationContext,
                context: transferContext
            )
        } catch {
            throw CoinageError.transferFailed(underlying: error)
        }
    }

    // MARK: Vouchers

    public func loadVouchers(
        amount: BigUInt,
        externalAssetHolder: any WalletManaging
    ) async throws {
        try await voucherService.load(
            amount: amount,
            externalAssetHolder: externalAssetHolder,
            breakdownContext: requireContext()
        )
    }

    public func coinageBalanceService() async throws -> CoinageBalanceServiceProtocol {
        if let service = cachedBalanceService {
            return service
        }
        let context = try await requireContext()
        // Re-check after suspension — setup may have created the service concurrently
        if let service = cachedBalanceService {
            return service
        }
        let service = CoinageBalanceService(
            denominationContext: context,
            voucherProvider: voucherProvider,
            coinProvider: coinProvider,
            logger: logger
        )
        service.start()
        cachedBalanceService = service
        return service
    }

    // MARK: Recovery

    public func recoverCoinsAndVouchers() async throws -> (coins: ScanResult<Coin>, vouchers: ScanResult<Voucher>) {
        async let coins = recoveryService.recoverCoins()
        async let vouchers = recoveryService.recoverVouchers()
        return try await (coins, vouchers)
    }

    public func extendScanCoinsAndVouchers(
        coinHorizon: Int,
        voucherHorizon: Int
    ) async throws -> (coins: ScanResult<Coin>, vouchers: ScanResult<Voucher>) {
        async let coins = recoveryService.extendScanCoins(from: coinHorizon)
        async let vouchers = recoveryService.extendScanVouchers(from: voucherHorizon)
        return try await (coins, vouchers)
    }

    public func recoverSpentCoinsOnChain() async throws -> BigUInt {
        let spentCoins = try await coinService.fetchAllCoins().filter { $0.state == .spent }
        guard !spentCoins.isEmpty else { return .zero }
        let secretKeys = try spentCoins.map { try coinKeypairFactory.derivePrivateKey(for: $0) }
        let context = try await denominationContext()
        return try await ongoingTransferService.revokeFromSecretKeys(
            secretKeys: secretKeys,
            context: context
        )
    }
}

// MARK: - Context Access

private extension CoinageService {
    /// Returns context immediately if available, or suspends until setup() posts a result.
    /// Propagates setup errors. Throws CancellationError if the task is cancelled while waiting.
    func requireContext() async throws -> DenominationBreakdownContext {
        if let existing = breakdownContext {
            return existing
        }
        for await result in contextSubject {
            guard let result else { continue }
            return try result.get()
        }
        throw CancellationError()
    }
}

// MARK: - Non-Degraded Amount

private extension CoinageService {
    func computeNonDegradedAmount(from result: CoinSelectionResult, context: DenominationBreakdownContext) -> BigUInt {
        switch result {
        case let .unloadIntoCoins(coins, perGroupAllocations):
            let coinsAmount = coins.reduce(BigUInt.zero) { $0 + context.valueInPlanks(for: $1.exponent) }
            let fullGroupsAmount = perGroupAllocations
                .filter { $0.vouchers.allSatisfy { $0.effectivePrivacy() == .full } }
                .reduce(BigUInt.zero) { sum, alloc in
                    alloc.recipientDenominations.reduce(sum) { $0 + context.valueInPlanks(for: $1.exponent) }
                }
            return coinsAmount + fullGroupsAmount
        case .exactMatch,
             .split:
            return .zero
        }
    }
}

// MARK: - Foreground Subscription

private extension CoinageService {
    func subscribeForeground() {
        guard appStateTask == nil else { return }

        let recyclingService = recyclingService
        let foregroundEvents = applicationStateStreamFactory.stream(for: .willEnterForeground)

        appStateTask = Task { [recyclingService] in
            for await _ in foregroundEvents {
                await recyclingService.scheduleRecycling()
            }
        }
    }
}
