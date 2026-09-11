import AsyncExtensions
import BigInt
import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import StateMachine
import SubstrateSdk
import SubstrateOperation

/// Dependencies needed to construct the external payment processing pipeline.
struct ExternalPaymentDependency {
    let instanceId: CoinageInstanceId
    let spendableAssets: any SpendableAssetsProviding
    let recycler: CoinageRecyclingServicing
    let voucherService: VoucherServiceProtocol
    let voucherKeyFactory: any VoucherKeyDeriving
    let voucherMinter: any VoucherMinting
    let recyclerLoader: RecyclerReadinessLoading
    let extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    let durability: any CoinageTxServicing
    let originFactory: OriginCreating
    let quotaTracker: any UnloadQuotaTracking
    let blockNumberProvider: BlockInfoProviding

    init(
        instanceId: CoinageInstanceId,
        spendableAssets: any SpendableAssetsProviding,
        recycler: CoinageRecyclingServicing,
        voucherService: VoucherServiceProtocol,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherMinter: any VoucherMinting,
        recyclerLoader: RecyclerReadinessLoading,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        durability: any CoinageTxServicing,
        originFactory: OriginCreating,
        quotaTracker: any UnloadQuotaTracking,
        blockNumberProvider: BlockInfoProviding
    ) {
        self.instanceId = instanceId
        self.spendableAssets = spendableAssets
        self.recycler = recycler
        self.voucherService = voucherService
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherMinter = voucherMinter
        self.recyclerLoader = recyclerLoader
        self.extrinsicMonitor = extrinsicMonitor
        self.durability = durability
        self.originFactory = originFactory
        self.quotaTracker = quotaTracker
        self.blockNumberProvider = blockNumberProvider
    }
}

/// Manages the lifecycle of external payments.
///
/// Previews payments via the planner, initiates by persisting to the store, and processes
/// non-terminal payments sequentially via the state machine. Thrown errors inside a state leave the
/// persisted stage untouched (``RetryPaymentState``) and are retried here under
/// ``ExternalPaymentRetryPolicy``; explicit verdicts persist `failed` immediately.
final class ExternalPaymentService: ExternalPaymentServicing, @unchecked Sendable {
    let store: ExternalPaymentStoring
    let planner: ExternalPaymentPlanning
    let stateMachineFactory: ExternalPaymentStateMachineCreating
    let context: ExternalPaymentContext
    let rescheduler: ExternalPaymentRescheduler
    let retryPolicy: ExternalPaymentRetryPolicy
    let logger: SDKLoggerProtocol?

    private let registrar: ExternalPaymentRegistrar
    private var observeTask: Task<Void, Never>?

    convenience init(
        store: ExternalPaymentStoring,
        dependency: ExternalPaymentDependency,
        retryPolicy: ExternalPaymentRetryPolicy = .production,
        logger: SDKLoggerProtocol? = nil
    ) {
        let planner = ExternalPaymentPlanner(spendableAssets: dependency.spendableAssets)
        let stateMachineFactory = ExternalPaymentStateMachineFactory(
            instanceId: dependency.instanceId,
            planner: planner,
            spendableAssets: dependency.spendableAssets,
            recycler: dependency.recycler,
            voucherService: dependency.voucherService,
            voucherKeyFactory: dependency.voucherKeyFactory,
            voucherMinter: dependency.voucherMinter,
            recyclerLoader: dependency.recyclerLoader,
            extrinsicMonitor: dependency.extrinsicMonitor,
            durability: dependency.durability,
            originFactory: dependency.originFactory,
            quotaTracker: dependency.quotaTracker,
            blockNumberProvider: dependency.blockNumberProvider,
            logger: logger
        )

        self.init(
            store: store,
            planner: planner,
            stateMachineFactory: stateMachineFactory,
            retryPolicy: retryPolicy,
            logger: logger
        )
    }

    init(
        store: ExternalPaymentStoring,
        planner: ExternalPaymentPlanning,
        stateMachineFactory: ExternalPaymentStateMachineCreating,
        retryPolicy: ExternalPaymentRetryPolicy = .production,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.planner = planner
        self.stateMachineFactory = stateMachineFactory
        self.retryPolicy = retryPolicy
        self.logger = logger
        context = ExternalPaymentContext(logger: logger)
        rescheduler = ExternalPaymentRescheduler(store: store, logger: logger)
        registrar = ExternalPaymentRegistrar(store: store)
    }

    func previewPayment(
        for amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview {
        let spendable = try await planner.plan(amount: amount, context: context, scope: .spendable)

        guard !spendable.isExecutable else { return spendable }

        let widened = try await planner.plan(amount: amount, context: context, scope: .withConfirmation)

        return widened.isExecutable ? widened : spendable
    }

    func initiatePayment(
        origin: String,
        paymentId: String,
        amountInPlanks: Balance,
        destination: AccountId,
        spendScope: SpendScope
    ) async throws {
        guard !paymentId.isEmpty else {
            throw ExternalPaymentError.invalidPaymentId
        }

        let payment = ExternalPayment(
            origin: origin,
            paymentId: paymentId,
            amountInPlanks: amountInPlanks,
            destination: destination,
            spendScope: spendScope
        )

        try await registrar.register(payment)
    }

    func subscribePaymentStatus(
        origin: String,
        paymentId: String
    ) throws -> AnyAsyncSequence<ExternalPaymentStatus> {
        let id = ExternalPayment.identifier(origin: origin, paymentId: paymentId)

        return store.observePayment(id: id)
            .map { payment -> ExternalPaymentStatus in
                guard let payment else { return .failed(reason: "unknown payment") }
                return payment.stage.toStatus(failureReason: payment.failureReason)
            }
            .removeDuplicates()
            .endAfterTerminal()
    }

    func setup(with context: DenominationBreakdownContext) {
        startObservation(with: context)
        rescheduler.setup()
    }

    func throttle() {
        observeTask?.cancel()
        observeTask = nil
        Task { [context] in await context.cancelAll() }
        rescheduler.throttle()
    }
}

// MARK: - Registration

/// Serializes check-then-save so two racing initiations for the same identity cannot both succeed.
private actor ExternalPaymentRegistrar {
    private let store: ExternalPaymentStoring

    init(store: ExternalPaymentStoring) {
        self.store = store
    }

    func register(_ payment: ExternalPayment) async throws {
        guard try await store.fetchPayment(byId: payment.id) == nil else {
            throw ExternalPaymentError.alreadyExists
        }

        try await store.save(payment: payment)
    }
}

// MARK: - Processing

private extension ExternalPaymentService {
    func startObservation(with denominationContext: DenominationBreakdownContext) {
        observeTask = Task { [store, context, logger, weak self] in
            do {
                for try await payments in store.observeNonTerminalPayments() {
                    let ready = payments
                        .filter { $0.readyAt <= Date() }
                        .sorted { $0.createdAt < $1.createdAt }

                    for payment in ready {
                        await context.scheduleIfNeeded(paymentId: payment.id) { [weak self] in
                            Task { [weak self] in
                                await self?.processPayment(
                                    id: payment.id,
                                    denominationContext: denominationContext
                                )
                            }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger?.error("Observation failed: \(error)")
            }
        }
    }

    func processPayment(id: String, denominationContext: DenominationBreakdownContext) async {
        logger?.debug("Processing payment \(id)")

        var attempt = 0

        while true {
            await runStateMachine(id: id, denominationContext: denominationContext)

            guard let payment = await reloadPayment(id: id), !payment.stage.isTerminal else { break }
            guard !Task.isCancelled else { return }

            if retryPolicy.hasWindowElapsed(since: payment.createdAt) {
                await persistRetryWindowElapsed(payment)
                break
            }

            attempt += 1
            let delay = retryPolicy.delay(forAttempt: attempt)
            logger?.debug("Payment \(id) retry #\(attempt) in \(delay)s: \(payment.failureReason ?? "-")")

            do {
                try await retryPolicy.sleep(delay)
            } catch {
                return
            }
        }

        await context.onComplete(paymentId: id)
    }

    func runStateMachine(id: String, denominationContext: DenominationBreakdownContext) async {
        do {
            let machine = try await stateMachineFactory.createStateMachine(
                for: id,
                store: store,
                context: denominationContext
            )
            _ = try await machine.executeUntilTerminal()
        } catch {
            logger?.error("Payment \(id) run failed: \(error)")
        }
    }

    func reloadPayment(id: String) async -> ExternalPayment? {
        do {
            return try await store.fetchPayment(byId: id)
        } catch {
            logger?.error("Payment \(id) reload failed: \(error)")
            return nil
        }
    }

    func persistRetryWindowElapsed(_ payment: ExternalPayment) async {
        var failed = payment
        failed.stage = payment.settledInPlanks > 0 ? .partiallyCompleted : .failed
        failed.failureReason = payment.failureReason ?? "retry window elapsed"
        failed.updatedAt = Date()

        do {
            try await store.save(payment: failed)
            logger?.error("Payment \(payment.id) failed after retry window: \(failed.failureReason ?? "")")
        } catch {
            logger?.error("Payment \(payment.id) could not persist failure: \(error)")
        }
    }
}

// MARK: - Helpers

private extension ExternalPayment.Stage {
    func toStatus(failureReason: String?) -> ExternalPaymentStatus {
        switch self {
        case .plan,
             .onboardCoins,
             .offboardVouchers:
            .processing
        case .completed,
             .partiallyCompleted:
            .completed
        case .failed:
            .failed(reason: failureReason ?? "Unknown")
        case .rescheduled:
            .processing
        }
    }
}

private extension ExternalPaymentStatus {
    var isTerminal: Bool {
        switch self {
        case .processing: false
        case .completed,
             .failed: true
        }
    }
}

private extension AsyncSequence where Element == ExternalPaymentStatus, Self: Sendable {
    /// Ends right after the first terminal status. `prefix(while:)` would only end once a *further*
    /// element arrived, which a settled row never produces.
    func endAfterTerminal() -> AnyAsyncSequence<ExternalPaymentStatus> {
        let upstream = self

        return AsyncThrowingStream<ExternalPaymentStatus, Error> { continuation in
            let task = Task {
                do {
                    for try await status in upstream {
                        continuation.yield(status)
                        if status.isTerminal { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }
}
