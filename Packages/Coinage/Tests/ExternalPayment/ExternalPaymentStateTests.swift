import Foundation
import Testing
@testable import Coinage

struct ExternalPaymentStateTests {
    private typealias Factory = ExternalPaymentTestFactory

    private let voucher = Factory.voucher(index: 1)

    private func assets(spendable vouchers: [Voucher]) -> StubSpendableAssetsProvider {
        StubSpendableAssetsProvider(assets: .make(spendableVouchers: vouchers))
    }

    // MARK: - Plan

    @Test func planReadyMovesToOffboarding() async {
        let planner =
            StubExternalPaymentPlanner(defaultResult: .success(.ready(Factory.selection(vouchers: [voucher]))))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment(spendScope: .withConfirmation))
            .transit(with: factory)

        #expect(await next.memo().stage == .offboardVouchers)
        #expect(!next.isTerminal)
        #expect(planner.scopes == [.withConfirmation])
    }

    @Test func planLoadCoinsMovesToOnboarding() async {
        let coin = Factory.coin(index: 9)
        let planner = StubExternalPaymentPlanner(defaultResult: .success(.loadCoins(Factory.selection(coins: [coin]))))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)

        #expect(await next.memo().stage == .onboardCoins)
    }

    @Test func planRescheduleIsTerminalWithReadyAt() async {
        let until = Date(timeIntervalSinceNow: 120)
        let planner = StubExternalPaymentPlanner(defaultResult: .success(.needsReschedule(
            after: until,
            Factory.selection()
        )))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .rescheduled)
        #expect(memo.readyAt == until)
    }

    @Test func planNotEnoughBalanceIsAVerdictAndFails() async {
        let planner = StubExternalPaymentPlanner(defaultResult: .success(.notEnoughBalance))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)
        let memo = await next.memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "Insufficient balance")
    }

    @Test func planThrowKeepsStageForRetry() async {
        let planner = StubExternalPaymentPlanner(defaultResult: .failure(StubExternalPaymentPlanner.Failure("rpc")))
        let factory = Factory.makeStateFactory(planner: planner)

        let next = await PlanPaymentState(payment: Factory.payment()).transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .plan)
        #expect(memo.failureReason == "rpc")
    }

    // MARK: - Onboard coins

    @Test func onboardSuccessReturnsToPlan() async {
        let recycler = StubCoinageRecyclingService()
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)
        let coins = [Factory.coin(index: 9)]

        let next = await OnboardCoinsPaymentState(payment: Factory.payment(), coins: coins).transit(with: factory)

        #expect(await next.memo().stage == .plan)
        #expect(await recycler.recycled == [coins])
    }

    @Test func onboardThrowKeepsStageForRetry() async {
        let recycler = StubCoinageRecyclingService(error: StubExternalPaymentPlanner.Failure("recycle"))
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner(), recycler: recycler)

        let next = await OnboardCoinsPaymentState(payment: Factory.payment(), coins: [Factory.coin(index: 9)])
            .transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .onboardCoins)
        #expect(memo.failureReason == "recycle")
    }

    // MARK: - Offboard vouchers

    @Test func offboardStalePlanReplans() async {
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(),
            assets: assets(spendable: []),
            txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)

        #expect(await next.memo().stage == .plan)
        #expect(txService.registrations.isEmpty)
    }

    @Test func offboardWithoutVerdictsReplansInsteadOfCommitting() async {
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(),
            assets: StubSpendableAssetsProvider(),
            txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)

        #expect(await next.memo().stage == .plan)
        #expect(txService.registrations.isEmpty)
    }

    @Test func offboardChecksSpendabilityUnderThePaymentScope() async {
        let assets = StubSpendableAssetsProvider()
        assets.set(.make(spendableVouchers: [voucher]), for: .withConfirmation)
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(),
            assets: assets,
            txService: txService
        )
        let payment = Factory.payment(spendScope: .withConfirmation)

        let next = await OffboardVouchersPaymentState(payment: payment, vouchers: [voucher]).transit(with: factory)

        #expect(await next.memo().stage == .completed)
        #expect(assets.requestedScopes == [.withConfirmation])
        #expect(txService.registrations == ["external-payment:\(payment.id)"])
    }

    @Test func offboardSuccessCompletesAndRegistersOnce() async {
        let txService = StubGroupTxService()
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(), assets: assets(spendable: [voucher]), txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)

        #expect(await next.memo().stage == .completed)
        #expect(txService.registrations.count == 1)
    }

    @Test func offboardPartialOutcomeIsPartiallyCompleted() async {
        let txService = StubGroupTxService()
        txService.setOutcome(.partial)
        let vouchers = [Factory.voucher(index: 1), Factory.voucher(index: 2, exponent: 2)]
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(), assets: assets(spendable: vouchers), txService: txService
        )
        let payment = Factory.payment(amount: Factory.planks(3) + Factory.planks(2))

        let next = await OffboardVouchersPaymentState(payment: payment, vouchers: vouchers).transit(with: factory)
        let memo = await next.memo()

        #expect(memo.stage == .partiallyCompleted)
        #expect(memo.failureReason == "1 of 2 unload transactions executed")
    }

    @Test func offboardFailedOutcomeIsAVerdict() async {
        let txService = StubGroupTxService()
        txService.setOutcome(.failure)
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(), assets: assets(spendable: [voucher]), txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)
        let memo = await next.memo()

        #expect(memo.stage == .failed)
        #expect(memo.failureReason == "no unload transaction executed")
    }

    @Test func offboardThrowKeepsStageForRetry() async {
        let txService = StubGroupTxService()
        txService.setSubmitError(StubExternalPaymentPlanner.Failure("submit"))
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(), assets: assets(spendable: [voucher]), txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: Factory.payment(), vouchers: [voucher])
            .transit(with: factory)
        let memo = await next.memo()

        #expect(next.isTerminal)
        #expect(memo.stage == .offboardVouchers)
        #expect(memo.failureReason == "submit")
    }

    @Test func offboardRejoinsPendingGroupWithoutRegisteringAgain() async {
        let txService = StubGroupTxService()
        let payment = Factory.payment()
        txService.seedGroup("external-payment:\(payment.id)", statuses: [.finalizedSuccess])
        let factory = Factory.makeStateFactory(
            planner: StubExternalPaymentPlanner(), assets: StubSpendableAssetsProvider(), txService: txService
        )

        let next = await OffboardVouchersPaymentState(payment: payment, vouchers: []).transit(with: factory)

        #expect(await next.memo().stage == .completed)
        #expect(txService.registrations.isEmpty)
    }

    @Test func memoRestoreReentersOffboardingAndPlanForOnboarding() async {
        let factory = Factory.makeStateFactory(planner: StubExternalPaymentPlanner())

        let offboarding = factory.stateFromMemo(payment: Factory.payment(stage: .offboardVouchers))
        let onboarding = factory.stateFromMemo(payment: Factory.payment(stage: .onboardCoins))

        #expect(await offboarding.memo().stage == .offboardVouchers)
        #expect(await onboarding.memo().stage == .plan)
    }
}
