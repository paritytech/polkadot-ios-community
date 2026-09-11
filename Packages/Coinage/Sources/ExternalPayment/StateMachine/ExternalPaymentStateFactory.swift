import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import StateMachine
import SubstrateOperation
import SubstrateSdk

/// Factory providing all dependencies and methods to create external payment states.
///
/// Passed to each state's ``StateMachineState/transit(with:)`` so states
/// can create their successors without coupling to concrete types.
final class ExternalPaymentStateFactory {
    let instanceId: CoinageInstanceId
    let planner: ExternalPaymentPlanning
    let context: DenominationBreakdownContext
    let voucherService: VoucherServiceProtocol
    let recycler: CoinageRecyclingServicing
    let voucherKeyFactory: any VoucherKeyDeriving
    let voucherMinter: any VoucherMinting
    let recyclerLoader: RecyclerReadinessLoading
    let durability: any CoinageTxServicing
    let originFactory: OriginCreating
    let quotaTracker: any UnloadQuotaTracking
    let blockNumberProvider: BlockInfoProviding
    let logger: SDKLoggerProtocol?

    init(
        instanceId: CoinageInstanceId,
        planner: ExternalPaymentPlanning,
        context: DenominationBreakdownContext,
        voucherService: VoucherServiceProtocol,
        recycler: CoinageRecyclingServicing,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherMinter: any VoucherMinting,
        recyclerLoader: RecyclerReadinessLoading,
        durability: any CoinageTxServicing,
        originFactory: OriginCreating,
        quotaTracker: any UnloadQuotaTracking,
        blockNumberProvider: BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.instanceId = instanceId
        self.planner = planner
        self.context = context
        self.voucherService = voucherService
        self.recycler = recycler
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherMinter = voucherMinter
        self.recyclerLoader = recyclerLoader
        self.durability = durability
        self.originFactory = originFactory
        self.quotaTracker = quotaTracker
        self.blockNumberProvider = blockNumberProvider
        self.logger = logger
    }
}

// MARK: - State Creation

extension ExternalPaymentStateFactory {
    typealias ErasedState = AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment>

    func makePlanState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(PlanPaymentState(payment: payment))
    }

    func makeOnboardCoinsState(payment: ExternalPayment, coins: [Coin], exactVouchers: [Voucher]) -> ErasedState {
        AnyStateMachineState(OnboardCoinsPaymentState(payment: payment, coins: coins, exactVouchers: exactVouchers))
    }

    func makeOffboardVouchersState(payment: ExternalPayment, vouchers: [Voucher]) -> ErasedState {
        AnyStateMachineState(OffboardVouchersPaymentState(payment: payment, vouchers: vouchers))
    }

    func makeCompletedState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(CompletedPaymentState(payment: payment))
    }

    func makeFailedState(payment: ExternalPayment, reason: String) -> ErasedState {
        logger?.error("Payment \(payment.id) failed: \(reason)")
        return AnyStateMachineState(FailedPaymentState(payment: payment, reason: reason))
    }

    func makePartiallyCompletedState(payment: ExternalPayment, reason: String) -> ErasedState {
        logger?
            .error(
                "Payment \(payment.id) short: settled \(payment.settledInPlanks) of \(payment.amountInPlanks) (\(reason))"
            )
        return AnyStateMachineState(PartiallyCompletedPaymentState(payment: payment, reason: reason))
    }

    /// Cancellation is not a verdict: keep `stage` so the next launch resumes the payment.
    func makeInterruptedState(payment: ExternalPayment, stage: ExternalPayment.Stage) -> ErasedState {
        AnyStateMachineState(InterruptedPaymentState(payment: payment, stage: stage))
    }

    /// Failure verdict, except for cancellation, which keeps the stage for the next launch.
    func makeFailedState(payment: ExternalPayment, stage: ExternalPayment.Stage, error: Error) -> ErasedState {
        error is CancellationError
            ? makeInterruptedState(payment: payment, stage: stage)
            : makeFailedState(payment: payment, reason: error.localizedDescription)
    }

    /// Restores a state from a persisted ``ExternalPayment`` memo.
    func stateFromMemo(payment: ExternalPayment) -> ErasedState {
        switch payment.stage {
        case .plan,
             .rescheduled:
            makePlanState(payment: payment)
        case .onboardCoins:
            // The first run's exact selection is not persisted: the state re-joins the recycling group
            // it registered (or re-plans if nothing was registered) and re-plans around the recycled
            // vouchers once they land.
            makeOnboardCoinsState(payment: payment, coins: [], exactVouchers: [])
        case .offboardVouchers:
            // Re-enter offboarding with no plan-carried vouchers: the service re-joins the durability
            // group this payment already registered and awaits its real outcome.
            makeOffboardVouchersState(payment: payment, vouchers: [])
        case .completed:
            makeCompletedState(payment: payment)
        case .failed:
            makeFailedState(payment: payment, reason: payment.failureReason ?? "Unknown")
        case .partiallyCompleted:
            makePartiallyCompletedState(payment: payment, reason: payment.failureReason ?? "Partial")
        }
    }
}
