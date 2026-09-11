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
        #expect(ExternalPayment.identifier(origin: "a", paymentId: "b:c") == "a:b:c")
    }

    @Test func paymentIdIsRecoveredFromIdentifier() {
        let restored = ExternalPayment(
            id: "getcash.dot:0x01",
            origin: "getcash.dot",
            amountInPlanks: 1,
            destination: Factory.destination
        )
        let legacy = ExternalPayment(
            id: "6F1E4A0C-LEGACY",
            origin: "5Recipient",
            amountInPlanks: 1,
            destination: Factory.destination
        )

        #expect(restored.paymentId == "0x01")
        #expect(legacy.paymentId == "6F1E4A0C-LEGACY")
        #expect(legacy.spendScope == .spendable)
    }

    @Test func terminalStages() {
        let terminal: Set<ExternalPayment.Stage> = [.completed, .failed, .rescheduled, .partiallyCompleted]

        for stage in [ExternalPayment.Stage.plan, .onboardCoins, .offboardVouchers, .completed, .failed,
                      .rescheduled, .partiallyCompleted] {
            #expect(stage.isTerminal == terminal.contains(stage), "\(stage)")
        }
    }

    @Test func retryPolicyBackoffIsLinearAndCapped() {
        let policy = ExternalPaymentRetryPolicy(window: 60, backoff: 30, maxBackoff: 100, sleep: { _ in })

        #expect(policy.delay(forAttempt: 1) == 30)
        #expect(policy.delay(forAttempt: 3) == 90)
        #expect(policy.delay(forAttempt: 4) == 100)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        #expect(!policy.hasWindowElapsed(since: createdAt, now: createdAt.addingTimeInterval(59)))
        #expect(policy.hasWindowElapsed(since: createdAt, now: createdAt.addingTimeInterval(60)))
    }
}
