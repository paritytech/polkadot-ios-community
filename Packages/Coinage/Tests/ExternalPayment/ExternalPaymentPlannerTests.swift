import SubstrateSdk
import Foundation
import Testing
@testable import Coinage

struct ExternalPaymentPlannerTests {
    private typealias Factory = ExternalPaymentTestFactory

    private let delay: TimeInterval = 6

    private func plan(
        _ assets: SpendableAssets?,
        amount: Balance,
        scope: SpendScope = .spendable
    ) async throws -> (ExternalPaymentPreview, StubSpendableAssetsProvider) {
        let provider = StubSpendableAssetsProvider()
        provider.set(assets, for: scope)
        let planner = ExternalPaymentPlanner(spendableAssets: provider, rescheduleDelay: delay)
        let preview = try await planner.plan(amount: amount, context: Factory.denomination, scope: scope)
        return (preview, provider)
    }

    @Test func spendableVouchersCoverAmountIsReady() async throws {
        let vouchers = [Factory.voucher(index: 1, exponent: 3), Factory.voucher(index: 2, exponent: 2)]
        let (preview, _) = try await plan(.make(spendableVouchers: vouchers), amount: Factory.planks(3))

        guard case let .ready(selection) = preview else {
            Issue.record("expected ready: \(preview)")
            return
        }
        #expect(selection.vouchers.map(\.derivationIndex) == [1])
        #expect(selection.coins.isEmpty)
        #expect(selection.scope == .spendable)
    }

    @Test func gainingVouchersRescheduleAtTheirReadyAtAndNeverTouchCoins() async throws {
        let readyAt = Date(timeIntervalSinceNow: 3_600)
        let assets = SpendableAssets.make(
            spendableCoins: [Factory.coin(index: 9, exponent: 4)],
            spendableVouchers: [Factory.voucher(index: 1, exponent: 2)],
            gainingPrivacyVouchers: [Factory.voucher(index: 2, exponent: 3, readyAt: readyAt)]
        )
        let (preview, _) = try await plan(assets, amount: Factory.planks(3))

        guard case let .needsReschedule(after, selection) = preview else {
            Issue.record("expected reschedule: \(preview)")
            return
        }
        #expect(abs(after.timeIntervalSince(readyAt)) < 1)
        #expect(selection.coins.isEmpty)
        #expect(selection.vouchers.map(\.derivationIndex) == [1])
    }

    @Test func rescheduleIsNeverEarlierThanTheBaseDelay() async throws {
        let assets = SpendableAssets.make(
            gainingPrivacyVouchers: [Factory.voucher(index: 2, exponent: 3, readyAt: .distantPast)]
        )
        let (preview, _) = try await plan(assets, amount: Factory.planks(3))

        guard case let .needsReschedule(after, _) = preview else {
            Issue.record("expected reschedule")
            return
        }
        #expect(after.timeIntervalSinceNow > delay - 1)
    }

    @Test func pendingVouchersCountTowardReschedule() async throws {
        let assets = SpendableAssets.make(pendingVouchers: [Factory.voucher(index: 3, exponent: 3)])
        let (preview, _) = try await plan(assets, amount: Factory.planks(3))

        guard case .needsReschedule = preview else {
            Issue.record("expected reschedule: \(preview)")
            return
        }
    }

    @Test func spendableCoinsCoverDeficitLoadsCoins() async throws {
        let assets = SpendableAssets.make(
            spendableCoins: [Factory.coin(index: 9, exponent: 3), Factory.coin(index: 8, exponent: 1)],
            spendableVouchers: [Factory.voucher(index: 1, exponent: 2)]
        )
        let (preview, _) = try await plan(assets, amount: Factory.planks(3) + Factory.planks(2))

        guard case let .loadCoins(selection) = preview else {
            Issue.record("expected loadCoins: \(preview)")
            return
        }
        #expect(selection.coins.map(\.derivationIndex) == [9])
        #expect(selection.vouchers.map(\.derivationIndex) == [1])
    }

    @Test func gainingOrPendingCoinsCoveringDeficitReschedule() async throws {
        let assets = SpendableAssets.make(
            gainingPrivacyCoins: [Factory.coin(index: 9, exponent: 2)],
            pendingCoins: [Factory.coin(index: 8, exponent: 2)]
        )
        let (preview, _) = try await plan(assets, amount: Factory.planks(3))

        guard case let .needsReschedule(_, selection) = preview else {
            Issue.record("expected reschedule: \(preview)")
            return
        }
        #expect(Set(selection.coins.map(\.derivationIndex)) == [9, 8])
    }

    @Test func nothingReachableIsNotEnoughBalance() async throws {
        let (preview, _) = try await plan(
            .make(spendableVouchers: [Factory.voucher(index: 1, exponent: 1)]),
            amount: Factory.planks(3)
        )

        guard case .notEnoughBalance = preview else {
            Issue.record("expected notEnoughBalance: \(preview)")
            return
        }
    }

    @Test func noVerdictsYetReschedulesInsteadOfUsingRawSets() async throws {
        let (preview, provider) = try await plan(nil, amount: Factory.planks(3), scope: .withConfirmation)

        guard case let .needsReschedule(after, selection) = preview else {
            Issue.record("expected reschedule: \(preview)")
            return
        }
        #expect(selection.vouchers.isEmpty && selection.coins.isEmpty)
        #expect(selection.scope == .withConfirmation)
        #expect(after.timeIntervalSinceNow > delay - 1)
        #expect(provider.requestedScopes == [.withConfirmation])
    }

    @Test func scopeIsPassedThroughToTheProvider() async throws {
        let (preview, provider) = try await plan(
            .make(spendableVouchers: [Factory.voucher(index: 1)]), amount: Factory.planks(3), scope: .withConfirmation
        )

        guard case let .ready(selection) = preview else {
            Issue.record("expected ready")
            return
        }
        #expect(selection.scope == .withConfirmation)
        #expect(provider.requestedScopes == [.withConfirmation])
    }
}
