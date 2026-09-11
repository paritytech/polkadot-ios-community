import Foundation
import Testing
@testable import Coinage

/// Durability scenario: a row persisted mid-flight by a "previous run" reaches a terminal stage in
/// a fresh service over the same store, without recycling or registering anything twice.
struct ExternalPaymentRestartTests {
    private typealias Factory = ExternalPaymentTestFactory

    private let voucher = Factory.voucher(index: 1)

    @Test func resumesFromPlanAndRegistersOnce() async throws {
        let payment = Factory.payment(stage: .plan)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.planner.setDefault(.success(.ready(Factory.selection(vouchers: [voucher]))))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.txService.registrations == [Factory.unloadGroupId(for: payment)])
        #expect(harness.recycler.submissions.isEmpty)
    }

    @Test func resumesOnboardingByRejoiningTheRecyclingGroup() async throws {
        let recycled = Factory.voucher(index: 2)
        let payment = Factory.payment(stage: .onboardCoins)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        let groupId = Factory.recycleGroupId(for: payment)
        harness.recycler.markExisting(groupId)
        harness.recycler.script(
            groupId: groupId,
            statuses: [.pending, .allRecycled(vouchers: [Factory.tracked(recycled)], finalized: false)]
        )
        harness.planner.setHandler { amount, mustInclude in
            .success(.ready(Factory.selection(vouchers: mustInclude, amount: amount)))
        }

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.recycler.submissions.isEmpty)
        #expect(harness.planner.calls.count == 1)
        #expect(harness.planner.calls.first?.mustInclude.map(\.derivationIndex) == [2])
        #expect(harness.txService.registrations == [Factory.unloadGroupId(for: payment)])
    }

    @Test func resumesOffboardingByRejoiningTheUnloadGroup() async throws {
        let payment = Factory.payment(stage: .offboardVouchers)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.txService.seedGroup(Factory.unloadGroupId(for: payment), statuses: [.finalizedSuccess])

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.txService.registrations.isEmpty)
        #expect(harness.planner.calls.isEmpty)
    }
}
