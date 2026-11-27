import Foundation
import Testing
@testable import polkadot_app

@Suite("ConfirmationGateRule")
struct ConfirmationGateRuleTests {
    @Test(
        "Asks above 50 Cash or above half of the total, and when the total is unknown",
        arguments: [
            (amount: Decimal(49), totalCash: Decimal?(1_000), expected: false),
            (amount: 50, totalCash: 1_000, expected: false),
            (amount: 51, totalCash: 1_000, expected: true),
            (amount: 19, totalCash: 40, expected: false),
            (amount: 20, totalCash: 40, expected: false),
            (amount: 21, totalCash: 40, expected: true),
            (amount: 1, totalCash: 0, expected: true),
            (amount: 1, totalCash: nil, expected: true)
        ]
    )
    func requiresAuthentication(amount: Decimal, totalCash: Decimal?, expected: Bool) {
        let rule = ConfirmationGateRule(absoluteLimit: 50, shareOfTotal: 0.5)
        #expect(rule.requiresAuthentication(amount: amount, totalCash: totalCash) == expected)
    }

    @Test(
        "Share is clamped to 0...1",
        arguments: [
            (shareOfTotal: Decimal(2), amount: Decimal(40), expected: false),
            (shareOfTotal: 2, amount: 41, expected: true),
            (shareOfTotal: -1, amount: 0, expected: false),
            (shareOfTotal: -1, amount: 0.01, expected: true)
        ]
    )
    func clampsShare(shareOfTotal: Decimal, amount: Decimal, expected: Bool) {
        let rule = ConfirmationGateRule(absoluteLimit: 1_000, shareOfTotal: shareOfTotal)
        #expect(rule.requiresAuthentication(amount: amount, totalCash: 40) == expected)
    }
}
