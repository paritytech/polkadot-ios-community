import Coinage
import Foundation
import Testing
@testable import polkadot_app

@Suite("PaymentPrivacyGate")
struct PaymentPrivacyGateTests {
    @Test("minPrivacy holds nothing back, so no confirmation")
    func minPrivacySkips() {
        #expect(!PaymentPrivacyGate.requiresPrivacyConfirmation(strategy: .minPrivacy))
    }

    @Test("every other preset requires the confirmation", arguments: [RecyclingStrategyType.balanced, .maxPrivacy])
    func othersRequire(strategy: RecyclingStrategyType) {
        #expect(PaymentPrivacyGate.requiresPrivacyConfirmation(strategy: strategy))
    }
}
