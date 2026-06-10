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
    private let walStore: TransferWALStoring
    private let originFactory: OriginCreating
    private let blockNumberProvider: BlockInfoProviding
    private let voucherService: VoucherServiceProtocol
    private let mortality: UInt32
    private let logger: SDKLoggerProtocol?

    init(
        planner: ExternalPaymentPlanning,
        recycler: CoinageRecyclingServicing,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherAllocator: any VoucherAllocating,
        recyclerLoader: RecyclerReadinessLoading,
        extrinsicMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        walStore: TransferWALStoring,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding,
        voucherService: VoucherServiceProtocol,
        mortality: UInt32 = CoinageConstants.walMortality,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.planner = planner
        self.recycler = recycler
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherAllocator = voucherAllocator
        self.recyclerLoader = recyclerLoader
        self.extrinsicMonitor = extrinsicMonitor
        self.walStore = walStore
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
        self.voucherService = voucherService
        self.mortality = mortality
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
        let coordinator = ExtrinsicSubmissionCoordinator(
            monitor: extrinsicMonitor,
            walStore: walStore,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        return ExternalPaymentStateFactory(
            planner: planner,
            context: context,
            recycler: recycler,
            voucherKeyFactory: voucherKeyFactory,
            voucherAllocator: voucherAllocator,
            recyclerLoader: recyclerLoader,
            coordinator: coordinator,
            walStore: walStore,
            originFactory: originFactory,
            blockNumberProvider: blockNumberProvider,
            voucherService: voucherService,
            mortality: mortality,
            logger: logger
        )
    }
}
