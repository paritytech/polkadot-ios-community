@testable import polkadot_app
import Testing

struct DeviceSyncRestartDelayPolicyTests {
    @Test("Backoff starts from one second and doubles")
    func delayDoublesByAttempt() {
        let policy = DeviceSyncRestartDelayPolicy()

        #expect(policy.delay(forAttempt: 0) == .seconds(1))
        #expect(policy.delay(forAttempt: 1) == .seconds(1))
        #expect(policy.delay(forAttempt: 2) == .seconds(2))
        #expect(policy.delay(forAttempt: 3) == .seconds(4))
        #expect(policy.delay(forAttempt: 4) == .seconds(8))
        #expect(policy.delay(forAttempt: 5) == .seconds(16))
    }

    @Test("Backoff is capped at thirty seconds")
    func delayIsCapped() {
        let policy = DeviceSyncRestartDelayPolicy()

        #expect(policy.delay(forAttempt: 6) == .seconds(30))
        #expect(policy.delay(forAttempt: 12) == .seconds(30))
    }
}
