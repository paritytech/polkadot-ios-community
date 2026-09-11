import AsyncExtensions
import Foundation
import SubstrateSdk
import Testing
@testable import Coinage

struct ExternalPaymentServiceTests {
    private typealias Factory = ExternalPaymentTestFactory

    private struct StreamDidNotEnd: Error {}

    /// Drains the stream to its end, failing if it has not ended within `timeout`.
    private func collect(
        _ sequence: AnyAsyncSequence<ExternalPaymentStatus>,
        timeout: TimeInterval = 2
    ) async throws -> [ExternalPaymentStatus] {
        try await withThrowingTaskGroup(of: [ExternalPaymentStatus].self) { group in
            group.addTask {
                var collected: [ExternalPaymentStatus] = []
                for try await status in sequence {
                    collected.append(status)
                }
                return collected
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw StreamDidNotEnd()
            }
            guard let first = try await group.next() else { throw StreamDidNotEnd() }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Initiation

    @Test func initiatePersistsPlanUnderScopedId() async throws {
        let harness = Factory.makeHarness()

        try await harness.service.initiatePayment(
            origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 8, destination: Factory.destination
        )

        let stored = try #require(harness.store.payment(id: "getcash.dot:0xab"))
        #expect(stored.stage == .plan)
        #expect(stored.origin == "getcash.dot")
        #expect(stored.paymentId == "0xab")
        #expect(stored.amountInPlanks == 8)
        #expect(stored.settledInPlanks == 0)
    }

    @Test func initiateRejectsReplayAndKeepsOriginalRow() async throws {
        let harness = Factory.makeHarness()
        try await harness.service.initiatePayment(
            origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 8, destination: Factory.destination
        )

        await #expect(throws: ExternalPaymentError.alreadyExists) {
            try await harness.service.initiatePayment(
                origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 99, destination: Factory.destination
            )
        }

        #expect(harness.store.all().count == 1)
        #expect(harness.store.payment(id: "getcash.dot:0xab")?.amountInPlanks == 8)
    }

    @Test func sameIdUnderAnotherOriginIsADifferentPayment() async throws {
        let harness = Factory.makeHarness()
        try await harness.service.initiatePayment(
            origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 8, destination: Factory.destination
        )
        try await harness.service.initiatePayment(
            origin: "other.dot", paymentId: "0xab", amountInPlanks: 8, destination: Factory.destination
        )

        #expect(harness.store.all().count == 2)
    }

    @Test func initiateRejectsEmptyId() async {
        let harness = Factory.makeHarness()

        await #expect(throws: ExternalPaymentError.invalidPaymentId) {
            try await harness.service.initiatePayment(
                origin: "getcash.dot", paymentId: "", amountInPlanks: 8, destination: Factory.destination
            )
        }
        #expect(harness.store.all().isEmpty)
    }

    // MARK: - Status

    @Test func unknownPaymentFailsOnceThenEnds() async throws {
        let harness = Factory.makeHarness()

        let statuses = try await collect(
            harness.service.subscribePaymentStatus(origin: "getcash.dot", paymentId: "0xnope")
        )

        #expect(statuses == [.failed(reason: "unknown payment")])
    }

    @Test(arguments: [
        (ExternalPayment.Stage.completed, ExternalPaymentStatus.completed),
        (.partiallyCompleted, .partiallyCompleted(settledInPlanks: 5)),
        (.failed, .failed(reason: "boom"))
    ])
    func coldSubscribeOnTerminalRowEmitsOnceThenEnds(
        stage: ExternalPayment.Stage,
        expected: ExternalPaymentStatus
    ) async throws {
        var payment = Factory.payment(settled: 5, stage: stage)
        payment.failureReason = "boom"
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))

        let statuses = try await collect(
            harness.service.subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
        )

        #expect(statuses == [expected])
    }

    @Test func legacyRescheduledReportsProcessing() async throws {
        let payment = Factory.payment(stage: .rescheduled)
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))

        var iterator = try harness.service
            .subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
            .makeAsyncIterator()

        #expect(try await iterator.next() == .processing)
    }

    @Test func processingDuplicatesCollapseAndStreamEndsOnCompletion() async throws {
        var payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        var iterator = try harness.service
            .subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
            .makeAsyncIterator()
        #expect(try await iterator.next() == .processing)

        payment.stage = .onboardCoins
        try await harness.store.save(payment: payment)
        payment.stage = .offboardVouchers
        try await harness.store.save(payment: payment)
        payment.stage = .completed
        try await harness.store.save(payment: payment)

        var rest: [ExternalPaymentStatus] = []
        while let status = try await iterator.next() {
            rest.append(status)
        }
        #expect(rest == [.completed])
    }

    // MARK: - Preview

    @Test func previewIsASinglePlannerPass() async throws {
        let harness = Factory.makeHarness()
        harness.planner.script([.success(.ready(Factory.selection(vouchers: [Factory.voucher(index: 1)])))])

        let preview = try await harness.service.previewPayment(for: 8, context: Factory.denomination)

        #expect(preview.isExecutable)
        #expect(harness.planner.calls.count == 1)
        #expect(harness.planner.calls.first?.mustInclude.isEmpty == true)
    }

    // MARK: - Processing

    @Test func readyPlanCompletesInOneRun() async throws {
        let payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        harness.planner.setDefault(.success(.ready(Factory.selection(vouchers: [Factory.voucher(index: 1)]))))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { harness.store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.store.payment(id: payment.id)?.settledInPlanks == payment.amountInPlanks)
        #expect(harness.txService.registrations == [Factory.unloadGroupId(for: payment)])
    }

    @Test func plannerErrorFailsTheRunWithoutRetry() async throws {
        let payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        harness.planner.setDefault(.failure(StubExternalPaymentPlanner.Failure("rpc down")))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { harness.store.payment(id: payment.id)?.stage == .failed }
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.store.payment(id: payment.id)?.failureReason == "rpc down")
        #expect(harness.planner.calls.count == 1)
    }

    @Test func partialUnloadIsTerminalAndReportsTheSettledAmount() async throws {
        let large = Factory.voucher(index: 1, exponent: 3)
        let small = Factory.voucher(index: 2, exponent: 2)
        let amount = Factory.planks(3) + Factory.planks(2)
        let payment = Factory.payment(amount: amount)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.vouchers.set(vouchers: [large, small])
        harness.txService.setOutcome(.partial)
        harness.planner.setDefault(.success(.ready(Factory.selection(vouchers: [large, small], amount: amount))))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .partiallyCompleted }
        let final = try #require(store.payment(id: payment.id))
        #expect([Factory.planks(3), Factory.planks(2)].contains(final.settledInPlanks))
        #expect(harness.txService.registrations.count == 1)
        #expect(harness.planner.calls.count == 1)

        let statuses = try await collect(
            harness.service.subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
        )
        #expect(statuses == [.partiallyCompleted(settledInPlanks: final.settledInPlanks)])
    }

    @Test func setupProcessesRowsInCreationOrder() async throws {
        let now = Date()
        let older = Factory.payment(paymentId: "0xa", amount: 8, createdAt: now.addingTimeInterval(-20))
        let newer = Factory.payment(paymentId: "0xb", amount: 16, createdAt: now.addingTimeInterval(-10))
        let store = InMemoryExternalPaymentStore(seed: [newer, older])
        let harness = Factory.makeHarness(store: store)
        harness.planner.setDefault(.success(.notEnoughBalance))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil {
            store.payment(id: older.id)?.stage == .failed && store.payment(id: newer.id)?.stage == .failed
        }
        #expect(harness.planner.amounts == [8, 16])
    }

    @Test func cancellationLeavesTheStageUntouched() async throws {
        let payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        harness.planner.blockUntilCancelled()

        harness.service.setup(with: Factory.denomination)
        await Factory.waitUntil { harness.planner.calls.count == 1 }

        harness.service.throttle()
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.store.payment(id: payment.id)?.stage == .plan)
        #expect(harness.store.payment(id: payment.id)?.failureReason == nil)
    }
}
