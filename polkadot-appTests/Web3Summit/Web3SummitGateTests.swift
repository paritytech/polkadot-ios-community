import Foundation
import Testing

@testable import polkadot_app

@Suite("Web3SummitGate decision")
struct Web3SummitGateTests {
    @Test("verificationDisabled always lands on main")
    func disabledAlwaysMain() {
        assertDecision(.main, mode: .verificationDisabled, verified: false)
        assertDecision(.main, mode: .verificationDisabled, verified: true)
    }

    @Test("verified flag overrides gate even when enabled")
    func verifiedOverridesGate() {
        assertDecision(.main, mode: .verificationEnabled, verified: true)
        assertDecision(.main, mode: .verificationEnabledSkippable, verified: true)
    }

    @Test("enabled and not verified routes to spa")
    func enabledNotVerifiedRoutesToSpa() {
        assertDecision(.spa, mode: .verificationEnabled, verified: false)
        assertDecision(.spa, mode: .verificationEnabledSkippable, verified: false)
    }

    @Test("W3S_ENDED locks the user out regardless of other state")
    func endedOverridesEverything() {
        assertDecision(.ended, mode: .ended, verified: false)
        assertDecision(.ended, mode: .ended, verified: true)
    }

    @Test("isSkippable only for VERIFICATION_ENABLED_SKIPPABLE")
    func skippableMode() {
        #expect(makeGate(mode: .verificationEnabledSkippable, verified: false).isSkippable)
        #expect(!makeGate(mode: .verificationEnabled, verified: false).isSkippable)
        #expect(!makeGate(mode: .verificationDisabled, verified: false).isSkippable)
        #expect(!makeGate(mode: .ended, verified: false).isSkippable)
    }

    private func assertDecision(
        _ expected: Web3SummitDestination,
        mode: Web3SummitGateMode,
        verified: Bool
    ) {
        #expect(makeGate(mode: mode, verified: verified).decide() == expected)
    }

    private func makeGate(mode: Web3SummitGateMode, verified: Bool) -> Web3SummitGate {
        Web3SummitGate(
            modeProvider: FakeModeProvider(mode: mode),
            verifiedStorage: FakeVerifiedStorage(verified: verified)
        )
    }
}

private struct FakeModeProvider: Web3SummitGateModeProviding {
    let mode: Web3SummitGateMode
    func current() -> Web3SummitGateMode { mode }
}

private final class FakeVerifiedStorage: Web3SummitVerifiedStoring {
    private var verified: Bool
    init(verified: Bool) { self.verified = verified }
    func isVerified() -> Bool { verified }
    func setVerified(_ value: Bool) { verified = value }
}
