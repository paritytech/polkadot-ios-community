import Foundation
import SDKLogger
import StateMachine

/// Unloads vouchers to external asset and transfers to destination.
///
/// Delegates to ``OffboardVouchersForPaymentService``; durability tracks the resulting asset state.
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
            voucherKeyFactory: factory.voucherKeyFactory,
            voucherMinter: factory.voucherMinter,
            recyclerLoader: factory.recyclerLoader,
            txService: factory.durability,
            originFactory: factory.originFactory,
            blockNumberProvider: factory.blockNumberProvider,
            denominationContext: factory.context,
            logger: factory.logger
        )

        do {
            try await service.execute(
                payment: payment,
                vouchers: vouchers
            )
            return factory.makeCompletedState(payment: payment)
        } catch {
            return factory.makeFailedState(
                payment: payment,
                reason: error.localizedDescription
            )
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .offboardVouchers
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
