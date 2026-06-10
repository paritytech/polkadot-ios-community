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
    let coinService: CoinServiceProtocol
    let voucherService: VoucherServiceProtocol
    let recycler: CoinageRecyclingServicing
    let voucherKeyFactory: any VoucherKeyDeriving
    let voucherAllocator: any VoucherAllocating
    let recyclerLoader: RecyclerReadinessLoading
    let extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    let walStore: TransferWALStoring
    let originFactory: OriginCreating
    let blockNumberProvider: BlockInfoProviding

    init(
        coinService: CoinServiceProtocol,
        voucherService: VoucherServiceProtocol,
        recycler: CoinageRecyclingServicing,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherAllocator: any VoucherAllocating,
        recyclerLoader: RecyclerReadinessLoading,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        walStore: TransferWALStoring,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding
    ) {
        self.coinService = coinService
        self.voucherService = voucherService
        self.recycler = recycler
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherAllocator = voucherAllocator
        self.recyclerLoader = recyclerLoader
        self.extrinsicMonitor = extrinsicMonitor
        self.walStore = walStore
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
    }
}

/// Manages the lifecycle of external payments.
///
/// Previews payments via the planner, initiates by persisting to the store,
/// and processes non-terminal payments sequentially via the state machine.
/// Also manages rescheduled payment wakeups.
final class ExternalPaymentService: ExternalPaymentServicing, @unchecked Sendable {
    let store: ExternalPaymentStoring
    let planner: ExternalPaymentPlanning
    let stateMachineFactory: ExternalPaymentStateMachineCreating
    let context: ExternalPaymentContext
    let rescheduler: ExternalPaymentRescheduler
    let logger: SDKLoggerProtocol?

    private var observeTask: Task<Void, Never>?

    init(
        store: ExternalPaymentStoring,
        dependency: ExternalPaymentDependency,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.logger = logger
        context = ExternalPaymentContext(logger: logger)
        rescheduler = ExternalPaymentRescheduler(store: store, logger: logger)

        planner = ExternalPaymentPlanner(
            coinService: dependency.coinService,
            voucherService: dependency.voucherService
        )

        stateMachineFactory = ExternalPaymentStateMachineFactory(
            planner: planner,
            recycler: dependency.recycler,
            voucherKeyFactory: dependency.voucherKeyFactory,
            voucherAllocator: dependency.voucherAllocator,
            recyclerLoader: dependency.recyclerLoader,
            extrinsicMonitor: dependency.extrinsicMonitor,
            walStore: dependency.walStore,
            originFactory: dependency.originFactory,
            blockNumberProvider: dependency.blockNumberProvider,
            voucherService: dependency.voucherService,
            logger: logger
        )
    }

    func previewPayment(
        for amount: Balance,
        context: DenominationBreakdownContext
    ) async throws -> ExternalPaymentPreview {
        try await planner.plan(amount: amount, context: context)
    }

    func initiatePayment(
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId
    ) async throws -> String {
        let id = UUID().uuidString

        let payment = ExternalPayment(
            id: id,
            origin: origin,
            amountInPlanks: amountInPlanks,
            destination: destination
        )

        try await store.save(payment: payment)

        return id
    }

    func subscribePaymentStatus(
        paymentId: String
    ) throws -> AnyAsyncSequence<ExternalPaymentStatus> {
        try store.observePayment(id: paymentId)
            .compactMap { payment -> ExternalPaymentStatus? in
                guard let payment else { return nil }
                return payment.stage.toStatus(failureReason: payment.failureReason)
            }
            .removeDuplicates()
            .endAfterTerminal()
            .eraseToAnyAsyncSequence()
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

        do {
            let machine = try await stateMachineFactory.createStateMachine(
                for: id,
                store: store,
                context: denominationContext
            )
            _ = try await machine.executeUntilTerminal()
        } catch {
            logger?.error("Payment \(id) failed: \(error)")
        }

        await context.onComplete(paymentId: id)
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
        case .completed:
            .completed
        case .failed:
            .failed(reason: failureReason ?? "Unknown")
        case .rescheduled:
            .processing
        }
    }
}

private extension AsyncSequence where Element == ExternalPaymentStatus {
    func endAfterTerminal() throws -> AnyAsyncSequence<ExternalPaymentStatus> {
        var finished = false

        let sequence = try prefix { status in
            guard !finished else { return false }

            switch status {
            case .processing:
                return true
            case .completed,
                 .failed:
                finished = true
                return true
            }
        }

        return sequence.eraseToAnyAsyncSequence()
    }
}
