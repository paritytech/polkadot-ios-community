import Foundation
import StateMachine

/// Terminal for the machine run, not for the payment: persists the stage that threw, unchanged,
/// with the error as `failureReason`. ``ExternalPaymentService`` detects "machine returned but the
/// persisted stage is still non-terminal" and re-runs under its retry policy.
struct RetryPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let stage: ExternalPayment.Stage
    let error: Error
    let isTerminal = true

    func transit(
        with _: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        AnyStateMachineState(self)
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = stage
        currentPayment.failureReason = error.localizedDescription
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
