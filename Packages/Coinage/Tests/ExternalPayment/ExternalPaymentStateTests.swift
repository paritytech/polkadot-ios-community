import Foundation
import SubstrateSdk
import Testing
@testable import Coinage

struct ExternalPaymentStateTests {
    private typealias Factory = ExternalPaymentTestFactory

    private let voucher = Factory.voucher(index: 1)
    private let coin = Factory.coin(index: 9)

    // MARK: - Plan

    @Test func planReadyMovesToOffboarding() async {
        let planner =
            StubExternalPaymentPlanner(defaultResult: .success(.ready(Factory.selection(vouchers: [voucher]))))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)

        #expect(await next.memo().stage == .offboardVouchers)
        #expect(!next.isTerminal)
        #expect(planner.calls.first?.mustInclude.isEmpty == true)
    }

    @Test func planLoadCoinsMovesToOnboardingWithExactVouchers() async {
        let selection = Factory.selection(vouchers: [voucher], coins: [coin], amount: Factory.planks(4))
        let planner = StubExternalPaymentPlanner(defaultResult: .success(.loadCoins(selection)))
        let recycler = StubCoinageRecyclingService()
        let payment = Factory.payment(amount: Factory.planks(4))
        recycler.script(groupId: Factory.recycleGroupId(for: payment), statuses: [])
        let factory = Factory.makeStateFactory(planner: planner, recycler: recycler)

        let next = await PlanPaymentState(payment: payment).transit(with: factory)
        #expect(await next.memo().stage == .onboardCoins)

        // Driving the onboarding state proves it carries the exact vouchers and coins of the plan.
        _ = await next.transit(with: factory)
        #expect(recycler.submissions == [.init(coins: [coin], groupId: Factory.recycleGroupId(for: payment))])
    }

    @Test func planNotEnoughBalanceIsAVerdict() async {
        let factory = Factory
            .makeStateFactory(planner: StubExternalPaymentPlanner(defaultResult: .success(.notEnoughBalance)))

        let memo = await PlanPaymentState(payment: Factory.payment()).transit(with: factory).memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "Insufficient balance")
    }

    @Test func planThrowFailsWithoutRetry() async {
        let planner = StubExternalPaymentPlanner(defaultResult: .failure(StubExternalPaymentPlanner.Failure("rpc")))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "rpc")
    }

    @Test func cancellationKeepsTheStage() async {
        let planner = StubExternalPaymentPlanner(defaultResult: .failure(CancellationError()))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .plan)
        #expect(memo.failureReason == nil)
    }

    // MARK: - Onboard coins

    @Test func onboardWaitsForRecyclingThenOffboardsWhenSufficient() async {
        let exact = Factory.voucher(index: 1, exponent: 2)
        let recycled = Factory.voucher(index: 2, exponent: 3)
        let payment = Factory.payment(amount: Factory.planks(3) + Factory.planks(2))
        let recycler = StubCoinageRecyclingService()
        let groupId = Factory.recycleGroupId(for: payment)
        recycler.script(
            groupId: groupId,
            statuses: [.pending, .allRecycled(vouchers: [Factory.tracked(recycled)], finalized: false)]
        )
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(),
            recycler: recycler,
            txService: txService,
            vouchers: [exact, recycled]
        )

        let next = await OnboardCoinsPaymentState(payment: payment, coins: [coin], exactVouchers: [exact])
            .transit(with: factory)

        #expect(await next.memo().stage == .offboardVouchers)
        #expect(recycler.submissions == [.init(coins: [coin], groupId: groupId)])
        _ = await next.transit(with: factory)
        #expect(txService.registrations == [Factory.unloadGroupId(for: payment)])
    }

    @Test func onboardFailsWhenRecycledVouchersStillFallShort() async {
        let payment = Factory.payment(amount: Factory.planks(5))
        let recycler = StubCoinageRecyclingService()
        recycler.script(
            groupId: Factory.recycleGroupId(for: payment),
            statuses: [.allRecycled(
                vouchers: [Factory.tracked(Factory.voucher(index: 2, exponent: 2))],
                finalized: true
            )]
        )
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)

        let memo = await OnboardCoinsPaymentState(payment: payment, coins: [coin], exactVouchers: [voucher])
            .transit(with: factory).memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "insufficient after recycling")
    }

    @Test func onboardFailsOnIncompleteRecyclingWithoutRetry() async {
        let payment = Factory.payment()
        let recycler = StubCoinageRecyclingService()
        recycler.script(groupId: Factory.recycleGroupId(for: payment), statuses: [.pending, .incomplete])
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)

        let memo = await OnboardCoinsPaymentState(payment: payment, coins: [coin], exactVouchers: [])
            .transit(with: factory).memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "recycling incomplete")
        #expect(recycler.submissions.count == 1)
    }

    @Test func onboardFailsWhenTheStreamEndsWithoutAVerdict() async {
        let payment = Factory.payment()
        let recycler = StubCoinageRecyclingService()
        recycler.script(groupId: Factory.recycleGroupId(for: payment), statuses: [.pending])
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)

        let memo = await OnboardCoinsPaymentState(payment: payment, coins: [coin], exactVouchers: [voucher])
            .transit(with: factory).memo()

        #expect(memo.stage == .failed)
    }

    @Test func onboardSubmissionErrorFails() async {
        let recycler = StubCoinageRecyclingService()
        recycler.setError(StubExternalPaymentPlanner.Failure("recycle"))
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)

        let memo = await OnboardCoinsPaymentState(payment: Factory.payment(), coins: [coin], exactVouchers: [voucher])
            .transit(with: factory).memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "recycle")
    }

    @Test func onboardReentryRejoinsTheGroupAndReplansAroundRecycledVouchers() async {
        let recycled = Factory.voucher(index: 2)
        let payment = Factory.payment()
        let recycler = StubCoinageRecyclingService()
        let groupId = Factory.recycleGroupId(for: payment)
        recycler.markExisting(groupId)
        recycler.script(
            groupId: groupId,
            statuses: [.allRecycled(vouchers: [Factory.tracked(recycled)], finalized: true)]
        )
        let planner = StubExternalPaymentPlanner()
        planner.setHandler { amount, mustInclude in
            mustInclude.map(\.derivationIndex) == [2]
                ? .success(.ready(Factory.selection(vouchers: mustInclude, amount: amount)))
                : .failure(StubExternalPaymentPlanner.Failure("unexpected plan"))
        }
        let factory = Factory.makeStateFactory(planner: planner, recycler: recycler)

        let next = await OnboardCoinsPaymentState(payment: payment, coins: [], exactVouchers: []).transit(with: factory)

        #expect(await next.memo().stage == .offboardVouchers)
        #expect(recycler.submissions.isEmpty)
        #expect(planner.calls.count == 1)
    }

    // MARK: - Offboard vouchers

    @Test func offboardSuccessCompletesWithFullSettlement() async {
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), txService: txService)
        let payment = Factory.payment()

        let memo = await OffboardVouchersPaymentState(payment: payment, vouchers: [voucher]).transit(with: factory)
            .memo()

        #expect(memo.stage == .completed)
        #expect(memo.settledInPlanks == payment.amountInPlanks)
        #expect(txService.registrations == [Factory.unloadGroupId(for: payment)])
    }

    @Test func offboardPartialOutcomeIsTerminalWithTheSettledValue() async {
        let txService = StubGroupTxService()
        txService.setOutcome(.partial)
        let vouchers = [Factory.voucher(index: 1, exponent: 3), Factory.voucher(index: 2, exponent: 2)]
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(),
            txService: txService,
            vouchers: vouchers
        )
        let payment = Factory.payment(amount: Factory.planks(3) + Factory.planks(2))

        let next = await OffboardVouchersPaymentState(payment: payment, vouchers: vouchers).transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .partiallyCompleted)
        #expect([Factory.planks(3), Factory.planks(2)].contains(memo.settledInPlanks))
        #expect(memo.failureReason == "1 of 2 unload transactions executed")
    }

    @Test func offboardFailedOutcomeIsAVerdict() async {
        let txService = StubGroupTxService()
        txService.setOutcome(.failure)
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), txService: txService)

        let memo = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory).memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "no unload transaction executed")
    }

    @Test func offboardSubmissionErrorFailsWithoutRetry() async {
        let txService = StubGroupTxService()
        txService.setSubmitError(StubExternalPaymentPlanner.Failure("submit"))
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), txService: txService)

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)
        let memo = await next.memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "submit")
    }

    @Test func offboardEmptyPlanFailsInsteadOfReplanning() async {
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), txService: txService)

        let memo = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: []).transit(with: factory)
            .memo()

        #expect(memo.stage == .failed)
        #expect(txService.registrations.isEmpty)
    }

    @Test func offboardRejoinsPendingGroupWithoutRegisteringAgain() async {
        let txService = StubGroupTxService()
        let payment = Factory.payment()
        txService.seedGroup(Factory.unloadGroupId(for: payment), statuses: [.finalizedSuccess])
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), txService: txService)

        let memo = await OffboardVouchersPaymentState(payment: payment, vouchers: []).transit(with: factory).memo()

        #expect(memo.stage == .completed)
        #expect(txService.registrations.isEmpty)
    }

    @Test func memoRestoreMapsLegacyAndMidFlightStages() async {
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner())

        #expect(await factory.stateFromMemo(payment: Factory.payment(stage: .rescheduled)).memo().stage == .plan)
        #expect(await factory.stateFromMemo(payment: Factory.payment(stage: .onboardCoins)).memo()
            .stage == .onboardCoins)
        #expect(await factory.stateFromMemo(payment: Factory.payment(stage: .offboardVouchers)).memo()
            .stage == .offboardVouchers)
    }
}
