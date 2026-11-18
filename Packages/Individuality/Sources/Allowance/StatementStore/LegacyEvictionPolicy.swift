import Foundation

/// Pre-#234 eviction rule: a slot may be taken over once the runtime's replacement cooldown has elapsed
/// since the entry was written. Candidates arrive ordered by priority and age, so the first match wins.
enum LegacyEvictionPolicy {
    static func firstCooledDown(
        _ candidates: [SSSEvictionCandidate],
        cooldown: UInt32,
        nowSeconds: UInt64
    ) -> SSSEvictionCandidate? {
        candidates.first { nowSeconds >= $0.since + UInt64(cooldown) }
    }
}
