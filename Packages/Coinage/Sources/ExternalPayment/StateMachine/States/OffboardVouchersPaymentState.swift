import Foundation
import SDKLogger
import StateMachine

/// Unloads vouchers to external asset and transfers to destination.
///
/// Creates ``ExternalPaymentTransferContext`` for reserve/process/revert
/// and delegates to ``OffboardVouchersForPaymentService``.
struct OffboardVouchersPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let vouchers: [Voucher]
    let isTerminal = false

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let transferContext = ExternalPaymentTransferContext(
            voucherService: factory.voucherService
        )

        let service = OffboardVouchersForPaymentService(
            voucherKeyFactory: factory.voucherKeyFactory,
            voucherAllocator: factory.voucherAllocator,
            recyclerLoader: factory.recyclerLoader,
            coordinator: factory.coordinator,
            walStore: factory.walStore,
            originFactory: factory.originFactory,
            blockNumberProvider: factory.blockNumberProvider,
            denominationContext: factory.context,
            mortality: factory.mortality,
            logger: factory.logger
        )

        do {
            try await service.execute(
                payment: payment,
                vouchers: vouchers,
                transferContext: transferContext
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
