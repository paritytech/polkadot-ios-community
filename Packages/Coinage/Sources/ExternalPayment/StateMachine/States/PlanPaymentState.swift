import Foundation
import StateMachine

/// Invokes the planner and decides the next state. Every outcome is a verdict: an unreachable amount
/// and any thrown error both persist `failed`; only a cancelled task keeps the stage.
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
                amount: payment.amountInPlanks,
                context: factory.context,
                mustInclude: []
            )

            switch plan {
            case let .ready(selection):
                return factory.makeOffboardVouchersState(payment: payment, vouchers: selection.vouchers)
            case let .loadCoins(selection):
                return factory.makeOnboardCoinsState(
                    payment: payment,
                    coins: selection.coins,
                    exactVouchers: selection.vouchers
                )
            case .notEnoughBalance:
                return factory.makeFailedState(payment: payment, reason: "Insufficient balance")
            }
        } catch {
            return factory.makeFailedState(payment: payment, stage: .plan, error: error)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .plan
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
