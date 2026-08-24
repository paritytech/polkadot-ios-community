import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import StateMachine
import SubstrateOperation

/// Creates configured ``StateMachine`` instances for external payments.
///
/// Constructs the ``ExternalPaymentStateFactory`` with all dependencies,
/// loads the initial state from the store, and returns a ready-to-run machine.
final class ExternalPaymentStateMachineFactory: ExternalPaymentStateMachineCreating {
    private let planner: ExternalPaymentPlanning
    private let recycler: CoinageRecyclingServicing
    private let voucherKeyFactory: any VoucherKeyDeriving
    private let voucherAllocator: any VoucherAllocating
    private let recyclerLoader: RecyclerReadinessLoading
    private let extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let blockNumberProvider: BlockInfoProviding
    private let voucherService: VoucherServiceProtocol
    private let logger: SDKLoggerProtocol?

    init(
        planner: ExternalPaymentPlanning,
        recycler: CoinageRecyclingServicing,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherAllocator: any VoucherAllocating,
        recyclerLoader: RecyclerReadinessLoading,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding,
        voucherService: VoucherServiceProtocol,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.planner = planner
        self.recycler = recycler
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherAllocator = voucherAllocator
        self.recyclerLoader = recyclerLoader
        self.extrinsicMonitor = extrinsicMonitor
        self.durability = durability
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
        self.voucherService = voucherService
        self.logger = logger
    }

    func createStateMachine(
        for paymentId: String,
        store: ExternalPaymentStoring,
        context: DenominationBreakdownContext
    ) async throws -> StateMachine<ExternalPaymentStateFactory, ExternalPayment> {
        let stateStore = ExternalPaymentStateStore(paymentId: paymentId, store: store)
        let payment = try await stateStore.loadStateMemo()
        let stateFactory = makeStateFactory(context: context)
        let initialState = stateFactory.stateFromMemo(payment: payment)

        return StateMachine(
            initialState: initialState,
            factory: stateFactory,
            store: AnyStateMachineStoring(stateStore)
        )
    }
}

private extension ExternalPaymentStateMachineFactory {
    func makeStateFactory(
        context: DenominationBreakdownContext
    ) -> ExternalPaymentStateFactory {
        ExternalPaymentStateFactory(
            planner: planner,
            context: context,
            recycler: recycler,
            voucherKeyFactory: voucherKeyFactory,
            voucherAllocator: voucherAllocator,
            recyclerLoader: recyclerLoader,
            durability: durability,
            originFactory: originFactory,
            blockNumberProvider: blockNumberProvider,
            voucherService: voucherService,
            logger: logger
        )
    }
}
