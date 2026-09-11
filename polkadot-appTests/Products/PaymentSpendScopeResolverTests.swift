import Coinage
import SubstrateSdk
import Foundation
import Testing
@testable import polkadot_app

@Suite("PaymentSpendScopeResolver")
struct PaymentSpendScopeResolverTests {
    private func balance(private amount: Balance, gaining: Balance, allowsConfirmed: Bool) -> CoinageBalance {
        CoinageBalance(
            availablePrivate: amount,
            gainingPrivacy: .init(amount: gaining, canSpendWithConfirmation: allowsConfirmed),
            pending: 0
        )
    }

    @Test("private funds cover the amount: spendable, no confirmation")
    func spendableWhenPrivateCovers() {
        let scope = PaymentSpendScopeResolver.resolve(
            balance: balance(private: 10, gaining: 5, allowsConfirmed: true),
            amount: 10
        )
        #expect(scope == .spendable)
    }

    @Test("balanced preset: gaining funds cover the shortfall behind a confirmation")
    func widensWhenStrategyAllows() {
        let scope = PaymentSpendScopeResolver.resolve(
            balance: balance(private: 4, gaining: 6, allowsConfirmed: true),
            amount: 10
        )
        #expect(scope == .withConfirmation)
    }

    @Test("max privacy preset: gaining funds are never offered")
    func neverWidensUnderMaxPrivacy() {
        let scope = PaymentSpendScopeResolver.resolve(
            balance: balance(private: 4, gaining: 6, allowsConfirmed: false),
            amount: 10
        )
        #expect(scope == nil)
    }

    @Test("even widened funds fall short")
    func unreachable() {
        let scope = PaymentSpendScopeResolver.resolve(
            balance: balance(private: 4, gaining: 5, allowsConfirmed: true),
            amount: 10
        )
        #expect(scope == nil)
    }
}
