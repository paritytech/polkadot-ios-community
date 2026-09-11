import Foundation
import Testing
@testable import Coinage

struct ExternalPaymentModelTests {
    private typealias Factory = ExternalPaymentTestFactory

    @Test func identityIsOriginScoped() {
        let first = Factory.payment(origin: "getcash.dot", paymentId: "0x01")
        let second = Factory.payment(origin: "other.dot", paymentId: "0x01")

        #expect(first.id == "getcash.dot:0x01")
        #expect(first.id != second.id)
        #expect(first.paymentId == second.paymentId)
    }

    @Test func paymentIdIsRecoveredFromIdentifier() {
        let restored = ExternalPayment(
            id: "getcash.dot:0x01", origin: "getcash.dot", amountInPlanks: 1, destination: Factory.destination
        )
        let legacy = ExternalPayment(
            id: "6F1E4A0C-LEGACY", origin: "5Recipient", amountInPlanks: 1, destination: Factory.destination
        )

        #expect(restored.paymentId == "0x01")
        #expect(legacy.paymentId == "6F1E4A0C-LEGACY")
        #expect(legacy.settledInPlanks == 0)
    }

    @Test func terminalStages() {
        let terminal: Set<ExternalPayment.Stage> = [.completed, .failed, .rescheduled, .partiallyCompleted]

        for stage in [ExternalPayment.Stage.plan, .onboardCoins, .offboardVouchers, .completed, .failed,
                      .rescheduled, .partiallyCompleted] {
            #expect(stage.isTerminal == terminal.contains(stage), "\(stage)")
        }
    }

    @Test func legacyRescheduledRowRestoresAsPlan() async {
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner())

        let restored = factory.stateFromMemo(payment: Factory.payment(stage: .rescheduled))

        #expect(!restored.isTerminal)
        #expect(await restored.memo().stage == .plan)
    }
}
