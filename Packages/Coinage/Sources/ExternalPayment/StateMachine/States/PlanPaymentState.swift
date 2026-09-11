import Foundation
import StateMachine

/// Invokes the planner and decides the next state.
///
/// Planner verdicts are final for this run (`notEnoughBalance` → failed); a thrown error is
/// transient and yields ``RetryPaymentState`` with the stage kept at `.plan`.
struct PlanPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let isTerminal = false

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        do {
            let plan = try await factory.planner.plan(
                amount: payment.remainingInPlanks,
                context: factory.context,
                scope: payment.spendScope
            )

            switch plan {
            case let .ready(selection):
                return factory.makeOffboardVouchersState(
                    payment: payment,
                    vouchers: selection.vouchers
                )
            case let .loadCoins(selection):
                return factory.makeOnboardCoinsState(payment: payment, coins: selection.coins)
            case let .needsReschedule(after, _):
                return factory.makeRescheduledState(payment: payment, until: after)
            case .notEnoughBalance:
                return factory.makeFailedOrPartial(payment: payment, reason: "Insufficient balance")
            }
        } catch {
            return factory.makeRetryState(payment: payment, stage: .plan, error: error)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .plan
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
