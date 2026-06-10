import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import StateMachine
import SubstrateOperation

/// Factory providing all dependencies and methods to create external payment states.
///
/// Passed to each state's ``StateMachineState/transit(with:)`` so states
/// can create their successors without coupling to concrete types.
final class ExternalPaymentStateFactory {
    let planner: ExternalPaymentPlanning
    let context: DenominationBreakdownContext
    let recycler: CoinageRecyclingServicing
    let voucherKeyFactory: any VoucherKeyDeriving
    let voucherAllocator: any VoucherAllocating
    let recyclerLoader: RecyclerReadinessLoading
    let coordinator: ExtrinsicSubmissionCoordinating
    let walStore: TransferWALStoring
    let originFactory: OriginCreating
    let blockNumberProvider: BlockInfoProviding
    let voucherService: VoucherServiceProtocol
    let mortality: UInt32
    let logger: SDKLoggerProtocol?

    init(
        planner: ExternalPaymentPlanning,
        context: DenominationBreakdownContext,
        recycler: CoinageRecyclingServicing,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherAllocator: any VoucherAllocating,
        recyclerLoader: RecyclerReadinessLoading,
        coordinator: ExtrinsicSubmissionCoordinating,
        walStore: TransferWALStoring,
        originFactory: OriginCreating,
        blockNumberProvider: BlockInfoProviding,
        voucherService: VoucherServiceProtocol,
        mortality: UInt32,
        logger: SDKLoggerProtocol?
    ) {
        self.planner = planner
        self.context = context
        self.recycler = recycler
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherAllocator = voucherAllocator
        self.recyclerLoader = recyclerLoader
        self.coordinator = coordinator
        self.walStore = walStore
        self.originFactory = originFactory
        self.blockNumberProvider = blockNumberProvider
        self.voucherService = voucherService
        self.mortality = mortality
        self.logger = logger
    }
}

// MARK: - State Creation

extension ExternalPaymentStateFactory {
    typealias ErasedState = AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment>

    func makePlanState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(PlanPaymentState(payment: payment))
    }

    func makeOnboardCoinsState(payment: ExternalPayment, coins: [Coin]) -> ErasedState {
        AnyStateMachineState(OnboardCoinsPaymentState(payment: payment, coins: coins))
    }

    func makeOffboardVouchersState(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) -> ErasedState {
        AnyStateMachineState(OffboardVouchersPaymentState(
            payment: payment,
            vouchers: vouchers
        ))
    }

    func makeCompletedState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(CompletedPaymentState(payment: payment))
    }

    func makeFailedState(payment: ExternalPayment, reason: String) -> ErasedState {
        AnyStateMachineState(FailedPaymentState(payment: payment, reason: reason))
    }

    func makeRescheduledState(payment: ExternalPayment, until: Date) -> ErasedState {
        AnyStateMachineState(RescheduledPaymentState(payment: payment, until: until))
    }

    /// Restores a state from a persisted ``ExternalPayment`` memo.
    func stateFromMemo(payment: ExternalPayment) -> ErasedState {
        switch payment.stage {
        case .plan:
            makePlanState(payment: payment)
        case .onboardCoins:
            // we don't have information about coins in the memo since the whole coinage state might be changed
            // as actual spending have not been started yet we fallback to planing again
            makePlanState(payment: payment)
        case .offboardVouchers:
            // we can't recover for now in cases when a user closed the app in the middle of the payment
            // however recovery service should eventually do the recover job
            // in result we can guarantee only partial payment here
            makeFailedState(payment: payment, reason: "Partial")
        case .completed:
            makeCompletedState(payment: payment)
        case .failed:
            makeFailedState(payment: payment, reason: payment.failureReason ?? "Unknown")
        case .rescheduled:
            makeRescheduledState(payment: payment, until: payment.readyAt)
        }
    }
}
