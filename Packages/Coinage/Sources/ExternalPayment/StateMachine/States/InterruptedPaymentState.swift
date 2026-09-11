import Foundation
import StateMachine

/// Terminal for the run, not for the payment: the task was cancelled (app throttled) mid-transition,
/// so the stage is persisted unchanged and the next `setup` picks the row up again. Every other
/// error is a verdict; only cancellation is not.
struct InterruptedPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let stage: ExternalPayment.Stage
    let isTerminal = true

    func transit(
        with _: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        AnyStateMachineState(self)
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = stage
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
