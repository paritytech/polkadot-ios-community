import Foundation
import Testing
@testable import Coinage

struct ExternalPaymentReschedulerTests {
    private typealias Factory = ExternalPaymentTestFactory

    @Test func pastReadyAtFlipsBackToPlan() async throws {
        let payment = Factory.payment(stage: .rescheduled, readyAt: Date(timeIntervalSinceNow: -1))
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let rescheduler = ExternalPaymentRescheduler(store: store)

        rescheduler.setup()
        defer { rescheduler.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .plan }
        let woken = try #require(store.payment(id: payment.id))
        #expect(woken.readyAt <= Date())
        #expect(woken.spendScope == payment.spendScope)
    }

    @Test func futureReadyAtStaysRescheduledUntilThen() async throws {
        let payment = Factory.payment(stage: .rescheduled, readyAt: .distantFuture)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let rescheduler = ExternalPaymentRescheduler(store: store)

        rescheduler.setup()
        defer { rescheduler.throttle() }
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.payment(id: payment.id)?.stage == .rescheduled)
    }
}
