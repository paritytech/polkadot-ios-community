import Foundation
import SDKLogger
import StateMachine

/// Unloads vouchers to external asset and transfers to destination.
///
/// Delegates to ``OffboardVouchersForPaymentService``; durability tracks the resulting asset state.
/// Unload verdicts (`.failed` outcome) persist `failed`; thrown errors keep the stage and retry.
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
            // Before committing, pick the path:
            // - a group is already registered (crash or retry re-entry): re-join and await it; the
            //   plan-carried vouchers are irrelevant since the inputs are already claimed.
            // - nothing registered yet: we must register, so the plan must still be valid — every
            //   selected voucher still spendable under the payment's scope. A stale or crash-lost
            //   plan re-plans instead of failing, because the funds are still there.
            if try await !service.hasPendingGroup(for: payment) {
                guard !vouchers.isEmpty, try await allSpendable(vouchers, factory: factory) else {
                    return factory.makePlanState(payment: payment)
                }
            }

            let outcome = try await service.execute(
                payment: payment,
                vouchers: vouchers
            )
            switch outcome {
            case .success:
                return factory.makeCompletedState(payment: payment)
            case let .partialSuccess(executed, total):
                return factory.makePartiallyCompletedState(
                    payment: payment,
                    reason: "\(executed) of \(total) unload transactions executed"
                )
            case .failed:
                return factory.makeFailedState(
                    payment: payment,
                    reason: "no unload transaction executed"
                )
            }
        } catch {
            return factory.makeRetryState(payment: payment, stage: .offboardVouchers, error: error)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .offboardVouchers
        currentPayment.updatedAt = Date()
        return currentPayment
    }

    /// Whether every planned voucher is still spendable under the payment's scope — the plan may
    /// have gone stale (a voucher spent, recycled, or held back by a strategy change) since it was
    /// picked. No verdicts yet means nothing is provably spendable.
    private func allSpendable(
        _ vouchers: [Voucher],
        factory: ExternalPaymentStateFactory
    ) async throws -> Bool {
        guard let assets = try await factory.spendableAssets.spendableAssets(scope: payment.spendScope) else {
            return false
        }

        let spendable = Set(assets.spendableVouchers.map(\.derivationIndex))
        return vouchers.allSatisfy { spendable.contains($0.derivationIndex) }
    }
}
