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
    let coinService: CoinServiceProtocol
    let voucherService: VoucherServiceProtocol
    let recycler: CoinageRecyclingServicing
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
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        recycler: CoinageRecyclingServicing,
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
        self.coinService = coinService
        self.voucherService = voucherService
        self.recycler = recycler
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
/// non-terminal payments sequentially via the state machine. Every run ends in a persisted verdict:
/// there is no retry and no reschedule — the product gets a terminal answer from one pass.
final class ExternalPaymentService: ExternalPaymentServicing, @unchecked Sendable {
    let store: ExternalPaymentStoring
    let planner: ExternalPaymentPlanning
    let stateMachineFactory: ExternalPaymentStateMachineCreating
    let context: ExternalPaymentContext
    let logger: SDKLoggerProtocol?

    private let registrar: ExternalPaymentRegistrar
    private var observeTask: Task<Void, Never>?

    convenience init(
        store: ExternalPaymentStoring,
        dependency: ExternalPaymentDependency,
        logger: SDKLoggerProtocol? = nil
    ) {
        let planner = ExternalPaymentPlanner(
            coinService: dependency.coinService,
            voucherService: dependency.voucherService
        )
        let stateMachineFactory = ExternalPaymentStateMachineFactory(
            instanceId: dependency.instanceId,
            planner: planner,
            voucherService: dependency.voucherService,
            recycler: dependency.recycler,
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

        self.init(store: store, planner: planner, stateMachineFactory: stateMachineFactory, logger: logger)
    }

    init(
        store: ExternalPaymentStoring,
        planner: ExternalPaymentPlanning,
        stateMachineFactory: ExternalPaymentStateMachineCreating,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.planner = planner
        self.stateMachineFactory = stateMachineFactory
        self.logger = logger
        context = ExternalPaymentContext(logger: logger)
        registrar = ExternalPaymentRegistrar(store: store)
    }

    func previewPayment(
        for amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview {
        try await planner.plan(amount: amount, context: context, mustInclude: [])
    }

    func initiatePayment(
        origin: String,
        paymentId: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws {
        guard !paymentId.isEmpty else {
            throw ExternalPaymentError.invalidPaymentId
        }

        let payment = ExternalPayment(
            origin: origin,
            paymentId: paymentId,
            amountInPlanks: amountInPlanks,
            destination: destination
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
                return payment.status
            }
            .removeDuplicates()
            .endAfterTerminal()
    }

    func setup(with context: DenominationBreakdownContext) {
        startObservation(with: context)
    }

    func throttle() {
        observeTask?.cancel()
        observeTask = nil
        Task { [context] in await context.cancelAll() }
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
                    for payment in payments.sorted(by: { $0.createdAt < $1.createdAt }) {
                        await context.scheduleIfNeeded(paymentId: payment.id) { [weak self] in
                            Task { [weak self] in
                                await self?.processPayment(id: payment.id, denominationContext: denominationContext)
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

    /// One machine run per payment; every state persists its own verdict, so nothing is retried here.
    func processPayment(id: String, denominationContext: DenominationBreakdownContext) async {
        logger?.debug("Processing payment \(id)")

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

        await context.onComplete(paymentId: id)
    }
}

// MARK: - Helpers

private extension ExternalPayment {
    var status: ExternalPaymentStatus {
        switch stage {
        case .plan,
             .onboardCoins,
             .offboardVouchers,
             .rescheduled:
            .processing
        case .completed:
            .completed
        case .partiallyCompleted:
            .partiallyCompleted(settledInPlanks: settledInPlanks)
        case .failed:
            .failed(reason: failureReason ?? "Unknown")
        }
    }
}

private extension ExternalPaymentStatus {
    var isTerminal: Bool {
        switch self {
        case .processing: false
        case .completed,
             .partiallyCompleted,
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
