import Foundation
import StateMachine
import SubstrateSdk

/// Recycles the selected coins under the payment's own durability group and awaits that group's
/// outcome through the recycler. On `allRecycled` (best-block inclusion is enough) it checks that the
/// exact vouchers plus the recycled ones cover the amount and moves to offboarding; `incomplete`,
/// a shortfall and any thrown error fail the payment — there are no retries.
///
/// A re-entered state (`exactVouchers` empty) re-joins the group instead of resubmitting and, once
/// the recycled vouchers land, re-plans with them forced in.
struct OnboardCoinsPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let coins: [Coin]
    let exactVouchers: [Voucher]
    let isTerminal = false

    static func recyclingGroupId(for payment: ExternalPayment) -> CoinageTxGroupId {
        "external-payment:\(payment.id):recycle"
    }

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let groupId = Self.recyclingGroupId(for: payment)

        do {
            try await factory.recycler.recycleCoins(coins, groupId: groupId)

            for try await status in factory.recycler.observeRecycling(groupId: groupId) {
                switch status {
                case .pending:
                    continue
                case .incomplete:
                    return factory.makeFailedState(payment: payment, reason: "recycling incomplete")
                case let .allRecycled(recycled, finalized):
                    factory.logger?.debug(
                        "Payment \(payment.id): \(recycled.count) vouchers recycled, finalized \(finalized)"
                    )
                    return try await continueWithRecycled(recycled.map(\.voucher), factory: factory)
                }
            }

            return factory.makeFailedState(payment: payment, reason: "recycling stream ended")
        } catch {
            return factory.makeFailedState(payment: payment, stage: .onboardCoins, error: error)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .onboardCoins
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}

private extension OnboardCoinsPaymentState {
    func continueWithRecycled(
        _ recycled: [Voucher],
        factory: ExternalPaymentStateFactory
    ) async throws -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        guard !exactVouchers.isEmpty else {
            return try await replan(including: recycled, factory: factory)
        }

        let vouchers = exactVouchers + recycled
        let covered = vouchers.reduce(Balance(0)) { $0 + factory.context.valueInPlanks(for: $1.exponent) }

        guard covered >= payment.amountInPlanks else {
            return factory.makeFailedState(payment: payment, reason: "insufficient after recycling")
        }

        return factory.makeOffboardVouchersState(payment: payment, vouchers: vouchers)
    }

    /// Re-entry path: the exact selection of the first run is unknown, so plan again around what
    /// this payment just recycled.
    func replan(
        including recycled: [Voucher],
        factory: ExternalPaymentStateFactory
    ) async throws -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let plan = try await factory.planner.plan(
            amount: payment.amountInPlanks,
            context: factory.context,
            mustInclude: recycled
        )

        guard case let .ready(selection) = plan else {
            return factory.makeFailedState(payment: payment, reason: "insufficient after recycling")
        }

        return factory.makeOffboardVouchersState(payment: payment, vouchers: selection.vouchers)
    }
}
