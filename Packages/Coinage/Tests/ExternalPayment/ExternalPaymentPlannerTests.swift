import Foundation
import SubstrateSdk
import Testing
@testable import Coinage

struct ExternalPaymentPlannerTests {
    private typealias Factory = ExternalPaymentTestFactory

    private func plan(
        vouchers: [TrackedVoucher] = [],
        coins: [TrackedCoin] = [],
        amount: Balance,
        mustInclude: [Voucher] = []
    ) async throws -> ExternalPaymentPreview {
        let planner = ExternalPaymentPlanner(
            coinService: StubCoinService(coins: coins),
            voucherService: StubVoucherService(vouchers: vouchers.map(\.voucher), states: vouchers)
        )
        return try await planner.plan(amount: amount, context: Factory.denomination, mustInclude: mustInclude)
    }

    @Test func spendableVouchersCoverTheAmountGreedily() async throws {
        let vouchers = [Factory.voucher(index: 1, exponent: 3), Factory.voucher(index: 2, exponent: 2)]
            .map { Factory.tracked($0) }

        let preview = try await plan(vouchers: vouchers, amount: Factory.planks(3))

        guard case let .ready(selection) = preview else {
            Issue.record("expected ready: \(preview)")
            return
        }
        #expect(selection.vouchers.map(\.derivationIndex) == [1])
        #expect(selection.coins.isEmpty)
    }

    @Test func mustIncludeVouchersComeFirst() async throws {
        let forced = Factory.voucher(index: 7, exponent: 1)
        let vouchers = [Factory.voucher(index: 1, exponent: 3), forced].map { Factory.tracked($0) }

        let preview = try await plan(
            vouchers: vouchers,
            amount: Factory.planks(3) + Factory.planks(1),
            mustInclude: [forced]
        )

        guard case let .ready(selection) = preview else {
            Issue.record("expected ready: \(preview)")
            return
        }
        #expect(selection.vouchers.map(\.derivationIndex) == [7, 1])
    }

    @Test func spendableCoinsCoverTheDeficit() async throws {
        let vouchers = [Factory.tracked(Factory.voucher(index: 1, exponent: 2))]
        let coins = [Factory.coin(index: 9, exponent: 3), Factory.coin(index: 8, exponent: 1)]
            .map { Factory.tracked($0) }

        let preview = try await plan(vouchers: vouchers, coins: coins, amount: Factory.planks(3) + Factory.planks(2))

        guard case let .loadCoins(selection) = preview else {
            Issue.record("expected loadCoins: \(preview)")
            return
        }
        #expect(selection.coins.map(\.derivationIndex) == [9])
        #expect(selection.vouchers.map(\.derivationIndex) == [1])
    }

    @Test func nonSelectableAssetsAreIgnored() async throws {
        let consumed = CoinageAssetState(handedOff: false, consumerStatus: .finalizedSuccess, minterStatus: nil)
        let vouchers = [
            Factory.tracked(Factory.voucher(index: 1, inRecycler: false)),
            Factory.tracked(Factory.voucher(index: 2), state: consumed)
        ]
        let coins = [
            Factory.tracked(Factory.coin(index: 9, isOnchain: false)),
            Factory.tracked(Factory.coin(index: 8), state: consumed)
        ]

        let preview = try await plan(vouchers: vouchers, coins: coins, amount: Factory.planks(1))

        guard case .notEnoughBalance = preview else {
            Issue.record("expected notEnoughBalance: \(preview)")
            return
        }
    }

    @Test func unreachableAmountIsNotEnoughBalance() async throws {
        let preview = try await plan(
            vouchers: [Factory.tracked(Factory.voucher(index: 1, exponent: 1))],
            amount: Factory.planks(3)
        )

        guard case .notEnoughBalance = preview else {
            Issue.record("expected notEnoughBalance: \(preview)")
            return
        }
    }
}
