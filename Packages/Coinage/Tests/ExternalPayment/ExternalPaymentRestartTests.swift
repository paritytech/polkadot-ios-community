import Foundation
import Testing
@testable import Coinage

/// Durability scenario: a row persisted mid-flight by a "previous run" reaches `completed` in a
/// fresh service over the same store, and the durability group is registered exactly once overall.
struct ExternalPaymentRestartTests {
    private typealias Factory = ExternalPaymentTestFactory

    private let voucher = Factory.voucher(index: 1)

    @Test(arguments: [ExternalPayment.Stage.plan, .onboardCoins])
    func resumesFromPrePlanStagesAndRegistersOnce(stage: ExternalPayment.Stage) async throws {
        let payment = Factory.payment(spendScope: .withConfirmation, stage: stage)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.planner.setDefault(.success(.ready(Factory.selection(vouchers: [voucher]))))
        harness.assets.set(.make(spendableVouchers: [voucher]), for: .withConfirmation)

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.txService.registrations == ["external-payment:\(payment.id)"])
        #expect(harness.planner.scopes == [.withConfirmation])
        #expect(store.payment(id: payment.id)?.spendScope == .withConfirmation)
    }

    @Test func resumesOffboardingByRejoiningTheRegisteredGroup() async throws {
        let payment = Factory.payment(stage: .offboardVouchers)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.txService.seedGroup("external-payment:\(payment.id)", statuses: [.finalizedSuccess])

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.txService.registrations.isEmpty)
        #expect(harness.planner.calls.isEmpty)
    }

    @Test func crashBeforeRegistrationReplansAndRegistersOnce() async throws {
        let payment = Factory.payment(stage: .offboardVouchers)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.planner.setDefault(.success(.ready(Factory.selection(vouchers: [voucher]))))
        harness.assets.set(.make(spendableVouchers: [voucher]), for: .spendable)

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.txService.registrations.count == 1)
        #expect(harness.planner.calls.count == 1)
    }
}
