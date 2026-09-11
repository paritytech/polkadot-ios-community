import SubstrateSdk
import AsyncExtensions
import Foundation
import Testing
@testable import Coinage

struct ExternalPaymentServiceTests {
    private typealias Factory = ExternalPaymentTestFactory

    private struct StreamDidNotEnd: Error {}

    /// Drains the stream to its end, failing if it has not ended within `timeout` — a status stream
    /// that never terminates is itself a defect the contract rules out.
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

    @Test func initiatePersistsPlanWithScopeUnderScopedId() async throws {
        let harness = Factory.makeHarness()

        try await harness.service.initiatePayment(
            origin: "getcash.dot",
            paymentId: "0xab",
            amountInPlanks: 8,
            destination: Factory.destination,
            spendScope: .withConfirmation
        )

        let stored = try #require(harness.store.payment(id: "getcash.dot:0xab"))
        #expect(stored.stage == .plan)
        #expect(stored.spendScope == .withConfirmation)
        #expect(stored.origin == "getcash.dot")
        #expect(stored.paymentId == "0xab")
        #expect(stored.amountInPlanks == 8)
    }

    @Test func initiateRejectsReplayAndKeepsOriginalRow() async throws {
        let harness = Factory.makeHarness()
        try await harness.service.initiatePayment(
            origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 8,
            destination: Factory.destination, spendScope: .withConfirmation
        )

        await #expect(throws: ExternalPaymentError.alreadyExists) {
            try await harness.service.initiatePayment(
                origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 99,
                destination: Factory.destination, spendScope: .spendable
            )
        }

        #expect(harness.store.all().count == 1)
        #expect(harness.store.payment(id: "getcash.dot:0xab")?.spendScope == .withConfirmation)
        #expect(harness.store.payment(id: "getcash.dot:0xab")?.amountInPlanks == 8)
    }

    @Test func sameIdUnderAnotherOriginIsADifferentPayment() async throws {
        let harness = Factory.makeHarness()
        try await harness.service.initiatePayment(
            origin: "getcash.dot", paymentId: "0xab", amountInPlanks: 8,
            destination: Factory.destination, spendScope: .spendable
        )
        try await harness.service.initiatePayment(
            origin: "other.dot", paymentId: "0xab", amountInPlanks: 8,
            destination: Factory.destination, spendScope: .spendable
        )

        #expect(harness.store.all().count == 2)
    }

    @Test func initiateRejectsEmptyId() async {
        let harness = Factory.makeHarness()

        await #expect(throws: ExternalPaymentError.invalidPaymentId) {
            try await harness.service.initiatePayment(
                origin: "getcash.dot", paymentId: "", amountInPlanks: 8,
                destination: Factory.destination, spendScope: .spendable
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
        (.partiallyCompleted, .partiallyCompleted(settledInPlanks: 0)),
        (.failed, .failed(reason: "boom"))
    ])
    func coldSubscribeOnTerminalRowEmitsOnceThenEnds(
        stage: ExternalPayment.Stage,
        expected: ExternalPaymentStatus
    ) async throws {
        var payment = Factory.payment(stage: stage)
        payment.failureReason = "boom"
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))

        let statuses = try await collect(
            harness.service.subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
        )

        #expect(statuses == [expected])
    }

    @Test func rescheduledReportsProcessing() async throws {
        let payment = Factory.payment(stage: .rescheduled, readyAt: .distantFuture)
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))

        var iterator = try harness.service
            .subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
            .makeAsyncIterator()

        #expect(try await iterator.next() == .processing)
    }

    @Test func processingDuplicatesCollapseAndStreamEndsOnCompletion() async throws {
        var payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        let sequence = try harness.service.subscribePaymentStatus(
            origin: payment.origin, paymentId: payment.paymentId
        )
        var iterator = sequence.makeAsyncIterator()
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

    @Test func previewWidensToConfirmationOnlyWhenSpendableCannotExecute() async throws {
        let harness = Factory.makeHarness()
        let widened = Factory.selection(vouchers: [Factory.voucher(index: 1)], scope: .withConfirmation)
        harness.planner.script([.success(.notEnoughBalance), .success(.ready(widened))])

        let preview = try await harness.service.previewPayment(for: 8, context: Factory.denomination)

        guard case let .ready(selection) = preview else {
            Issue.record("expected ready, got \(preview)")
            return
        }
        #expect(selection.scope == .withConfirmation)
        #expect(harness.planner.scopes == [.spendable, .withConfirmation])
    }

    @Test func previewKeepsSpendableResultWhenWideningDoesNotHelp() async throws {
        let harness = Factory.makeHarness()
        let spendable = ExternalPaymentPreview.needsReschedule(after: Date(), Factory.selection())
        harness.planner.script([.success(spendable), .success(.notEnoughBalance)])

        let preview = try await harness.service.previewPayment(for: 8, context: Factory.denomination)

        guard case .needsReschedule = preview else {
            Issue.record("expected the spendable reschedule verdict, got \(preview)")
            return
        }
        #expect(harness.planner.scopes == [.spendable, .withConfirmation])
    }

    @Test func previewDoesNotWidenWhenSpendableExecutes() async throws {
        let harness = Factory.makeHarness()
        harness.planner.script([.success(.ready(Factory.selection(vouchers: [Factory.voucher(index: 1)])))])

        _ = try await harness.service.previewPayment(for: 8, context: Factory.denomination)

        #expect(harness.planner.scopes == [.spendable])
    }

    // MARK: - Processing

    @Test func transientPlannerErrorKeepsStageRetriesThenCompletes() async throws {
        let payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        let voucher = Factory.voucher(index: 1)
        harness.planner.script([
            .failure(StubExternalPaymentPlanner.Failure("rpc down")),
            .success(.ready(Factory.selection(vouchers: [voucher])))
        ])
        harness.assets.set(.make(spendableVouchers: [voucher]), for: .spendable)

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { harness.store.payment(id: payment.id)?.stage == .completed }
        #expect(harness.sleeper.recorded == [30])
        #expect(harness.planner.calls.count == 2)
        #expect(harness.txService.registrations.count == 1)
    }

    @Test func partialUnloadSettlesAndPaysTheRemainderInANewRound() async throws {
        let large = Factory.voucher(index: 1, exponent: 3)
        let small = Factory.voucher(index: 2, exponent: 2)
        let amount = Factory.planks(3) + Factory.planks(2)
        let payment = Factory.payment(amount: amount)
        let store = InMemoryExternalPaymentStore(seed: [payment])
        let harness = Factory.makeHarness(store: store)
        harness.vouchers.set(vouchers: [large, small])
        harness.assets.set(.make(spendableVouchers: [large, small]), for: .spendable)
        harness.txService.setOutcomes([.partial, .success])
        harness.planner.setHandler { remaining, _ in
            let selection = remaining == amount ? [large, small] : [remaining == Factory.planks(3) ? large : small]
            return .success(.ready(Factory.selection(vouchers: selection, amount: remaining)))
        }

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: payment.id)?.stage == .completed }
        let final = try #require(store.payment(id: payment.id))
        #expect(final.settledInPlanks == amount)
        #expect(final.round == 1)
        #expect(harness.txService.registrations == [
            "external-payment:\(payment.id)", "external-payment:\(payment.id):r1"
        ])
        #expect(harness.planner.amounts.count == 2)
        #expect(harness.planner.amounts.last.map { $0 < amount } == true)
        #expect(harness.sleeper.recorded.isEmpty)
    }

    @Test func retryWindowElapsedAfterASettledRoundIsPartiallyCompleted() async throws {
        let payment = Factory.payment(round: 1, settled: 4, createdAt: Date(timeIntervalSinceNow: -10))
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]), retryWindow: 5)
        harness.planner.setDefault(.failure(StubExternalPaymentPlanner.Failure("still down")))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store(harness).payment(id: payment.id)?.stage.isTerminal == true }
        #expect(store(harness).payment(id: payment.id)?.stage == .partiallyCompleted)
    }

    private func store(_ harness: ExternalPaymentHarness) -> InMemoryExternalPaymentStore { harness.store }

    @Test func partialCompletionReportsTheSettledAmount() async throws {
        let payment = Factory.payment(amount: 12, round: 1, settled: 8, stage: .partiallyCompleted)
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))

        let statuses = try await collect(
            harness.service.subscribePaymentStatus(origin: payment.origin, paymentId: payment.paymentId)
        )

        #expect(statuses == [.partiallyCompleted(settledInPlanks: 8)])
    }

    @Test func backoffReleasesTheProcessingSlotForOtherPayments() async throws {
        let now = Date()
        let stuck = Factory.payment(paymentId: "0xa", amount: 8, createdAt: now.addingTimeInterval(-20))
        let next = Factory.payment(paymentId: "0xb", amount: 16, createdAt: now.addingTimeInterval(-10))
        let store = InMemoryExternalPaymentStore(seed: [stuck, next])
        let harness = Factory.makeHarness(store: store)
        let voucher = Factory.voucher(index: 1, exponent: 4)
        harness.assets.set(.make(spendableVouchers: [voucher]), for: .spendable)
        harness.planner.setHandler { amount, _ in
            amount == 8
                ? .failure(StubExternalPaymentPlanner.Failure("rpc down"))
                : .success(.ready(Factory.selection(vouchers: [voucher], amount: amount)))
        }
        harness.sleeper.hold()

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { store.payment(id: next.id)?.stage == .completed }
        #expect(store.payment(id: stuck.id)?.stage == .plan)
        #expect(harness.sleeper.recorded == [30])
        #expect(harness.planner.amounts == [8, 16])

        harness.sleeper.release()
        await Factory.waitUntil { harness.planner.amounts.count >= 3 }
        #expect(harness.planner.amounts.dropFirst(2).allSatisfy { $0 == 8 })
    }

    @Test func retryWindowElapsedPersistsFailedWithLastError() async throws {
        let payment = Factory.payment(createdAt: Date(timeIntervalSinceNow: -10))
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]), retryWindow: 5)
        harness.planner.setDefault(.failure(StubExternalPaymentPlanner.Failure("still down")))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil { harness.store.payment(id: payment.id)?.stage == .failed }
        #expect(harness.store.payment(id: payment.id)?.failureReason == "still down")
        #expect(harness.sleeper.recorded.isEmpty)
        #expect(harness.planner.calls.count == 1)
    }

    @Test func cancellationNeverPersistsFailed() async throws {
        let payment = Factory.payment()
        let harness = Factory.makeHarness(store: InMemoryExternalPaymentStore(seed: [payment]))
        harness.planner.blockUntilCancelled()

        harness.service.setup(with: Factory.denomination)
        await Factory.waitUntil { harness.planner.calls.count == 1 }

        harness.service.throttle()
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.store.payment(id: payment.id)?.stage == .plan)
        #expect(harness.sleeper.recorded.isEmpty)
    }

    @Test func setupProcessesReadyRowsInCreationOrderAndSkipsFutureReadyAt() async throws {
        let now = Date()
        let older = Factory.payment(paymentId: "0xa", amount: 8, createdAt: now.addingTimeInterval(-20))
        let newer = Factory.payment(paymentId: "0xb", amount: 16, createdAt: now.addingTimeInterval(-10))
        let notYet = Factory.payment(paymentId: "0xc", amount: 32, readyAt: .distantFuture, createdAt: now)
        let store = InMemoryExternalPaymentStore(seed: [newer, notYet, older])
        let harness = Factory.makeHarness(store: store, retryWindow: 0)
        harness.planner.setDefault(.success(.notEnoughBalance))

        harness.service.setup(with: Factory.denomination)
        defer { harness.service.throttle() }

        await Factory.waitUntil {
            store.payment(id: older.id)?.stage == .failed && store.payment(id: newer.id)?.stage == .failed
        }
        #expect(harness.planner.amounts == [8, 16])
        #expect(store.payment(id: notYet.id)?.stage == .plan)
    }
}
