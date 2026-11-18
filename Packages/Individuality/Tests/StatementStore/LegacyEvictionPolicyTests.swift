import Foundation
import Testing
@testable import Individuality

struct LegacyEvictionPolicyTests {
    private let keyManager = FakeBandersnatchKeyManaging()

    @Test(arguments: [(UInt64(1_000), true), (UInt64(999), false)])
    func cooldownBoundaryIsInclusive(now: UInt64, eligible: Bool) {
        let candidate = makeCandidate(seq: 0, since: 900)

        let picked = LegacyEvictionPolicy.firstCooledDown([candidate], cooldown: 100, nowSeconds: now)

        #expect((picked != nil) == eligible)
    }

    @Test func firstCooledDownInGivenOrderWins() {
        let candidates = [
            makeCandidate(seq: 0, since: 990),
            makeCandidate(seq: 1, since: 500),
            makeCandidate(seq: 2, since: 100)
        ]

        let picked = LegacyEvictionPolicy.firstCooledDown(candidates, cooldown: 100, nowSeconds: 1_000)

        #expect(picked?.seq == 1)
    }

    @Test func noCandidatesGivesNil() {
        #expect(LegacyEvictionPolicy.firstCooledDown([], cooldown: 0, nowSeconds: 0) == nil)
    }
}

private extension LegacyEvictionPolicyTests {
    func makeCandidate(seq: UInt32, since: UInt64) -> SSSEvictionCandidate {
        SSSEvictionCandidate(
            personOrigin: .lite(0, keyManager),
            seq: seq,
            alias: Data(repeating: UInt8(seq), count: 32),
            holder: Data(repeating: 0xA0 + UInt8(seq), count: 32),
            since: since,
            signerKeyId: nil
        )
    }
}
