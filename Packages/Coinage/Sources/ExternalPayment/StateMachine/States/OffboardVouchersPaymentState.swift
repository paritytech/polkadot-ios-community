import Foundation
import SDKLogger
import StateMachine

/// Unloads vouchers to external asset and transfers to destination.
///
/// Submits straight to ``OffboardVouchersForPaymentService`` — the plan was validated moments ago and
/// the service re-joins an already registered group on its own (the crash path). Every outcome is a
/// verdict: `.success` completes, `.partialSuccess` persists what settled as `partiallyCompleted`,
/// `.failed`, a submission failure and any thrown error persist `failed`.
struct OffboardVouchersPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let vouchers: [Voucher]
    let isTerminal = false

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let service = OffboardVouchersForPaymentService(
            instanceId: factory.instanceId,
            voucherKeyFactory: factory.voucherKeyFactory,
            voucherService: factory.voucherService,
            voucherMinter: factory.voucherMinter,
            recyclerLoader: factory.recyclerLoader,
            txService: factory.durability,
            originFactory: factory.originFactory,
            quotaTracker: factory.quotaTracker,
            blockNumberProvider: factory.blockNumberProvider,
            denominationContext: factory.context,
            logger: factory.logger
        )

        do {
            switch try await service.execute(payment: payment, vouchers: vouchers) {
            case .success:
                var settled = payment
                settled.settledInPlanks = payment.amountInPlanks
                return factory.makeCompletedState(payment: settled)
            case let .partialSuccess(settledInPlanks, executed, total):
                var settled = payment
                settled.settledInPlanks = settledInPlanks
                return factory.makePartiallyCompletedState(
                    payment: settled,
                    reason: "\(executed) of \(total) unload transactions executed"
                )
            case .failed:
                return factory.makeFailedState(payment: payment, reason: "no unload transaction executed")
            }
        } catch {
            return factory.makeFailedState(payment: payment, stage: .offboardVouchers, error: error)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .offboardVouchers
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
