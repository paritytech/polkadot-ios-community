import Foundation
import SubstrateSdk
import Individuality

/// Remaining free-unload tokens this period, together with the period allowance so callers can
/// express a reserve as a fraction of the limit rather than a fixed count.
public struct UnloadQuota: Equatable, Sendable {
    public let remaining: Int
    public let limit: Int

    public init(remaining: Int, limit: Int) {
        self.remaining = remaining
        self.limit = limit
    }
}

/// Reads how much free-unload quota is left, so the recycling quota valve can auto-manage privacy
/// once the allowance runs low. Quota is consumed at unload time and scales with the number of unload
/// batches, so a high-privacy strategy raises pressure here.
public protocol UnloadQuotaTracking: Sendable {
    func remainingQuota() async throws -> UnloadQuota
    /// Decrements the cached estimate after a successful unload rather than re-walking the range.
    func noteUnloadHappened() async
}

/// Counts unconsumed counters across the valid periods, caching the result for the current period.
/// The count is exact while tokens are consumed in index order (which `UnloadTokenResolver` does).
public actor UnloadQuotaTracker: UnloadQuotaTracking {
    private let runtimeCodingService: RuntimeCodingServiceProtocol
    private let consumedTokenChecker: any ConsumedTokenChecking
    private let personOriginProvider: any OriginPersonProviding

    private struct Cache {
        let period: UInt32
        var quota: UnloadQuota
    }

    private var cache: Cache?
    private var unloadsSinceWalk = 0

    /// A full re-walk every this many unloads bounds incremental drift from the decrement path.
    private static let unloadsBeforeRefresh = 5

    public init(
        runtimeCodingService: RuntimeCodingServiceProtocol,
        consumedTokenChecker: any ConsumedTokenChecking,
        personOriginProvider: any OriginPersonProviding
    ) {
        self.runtimeCodingService = runtimeCodingService
        self.consumedTokenChecker = consumedTokenChecker
        self.personOriginProvider = personOriginProvider
    }

    public func remainingQuota() async throws -> UnloadQuota {
        let periodDuration: UInt64 = try await runtimeCodingService.fetchConstant(
            path: CoinagePallet.Constants.unloadTokenTimePeriod(),
            type: UInt64.self
        )
        let maxCounter: UInt32 = try await runtimeCodingService.fetchConstant(
            path: CoinagePallet.Constants.maxFreeUnloadTokensPerTimePeriod(),
            type: UInt32.self
        )

        let periods = UnloadTokenPeriodCalculator.validPeriods(
            currentDate: Date(),
            periodDuration: periodDuration
        )
        let currentPeriod = periods.last ?? 0

        // Cache keyed by current period, so a period boundary invalidates it for free.
        if let cache, cache.period == currentPeriod {
            return cache.quota
        }

        let quota = try await walk(periods: periods, maxCounter: maxCounter)
        cache = Cache(period: currentPeriod, quota: quota)
        unloadsSinceWalk = 0
        return quota
    }

    public func noteUnloadHappened() {
        unloadsSinceWalk += 1

        if unloadsSinceWalk >= Self.unloadsBeforeRefresh {
            cache = nil
            unloadsSinceWalk = 0
        } else if let current = cache {
            let decremented = UnloadQuota(
                remaining: max(0, current.quota.remaining - 1),
                limit: current.quota.limit
            )
            cache = Cache(period: current.period, quota: decremented)
        }
    }
}

private extension UnloadQuotaTracker {
    func walk(periods: [UInt32], maxCounter: UInt32) async throws -> UnloadQuota {
        guard maxCounter > 0 else { return UnloadQuota(remaining: 0, limit: 0) }

        let pickedPerson = try await personOriginProvider.pickPersonOrigin()
        let aliasProvider = pickedPerson.makeAliasProvider()

        var remaining = 0
        for period in periods {
            let queries: [(period: UInt32, alias: Data)] = try (0 ..< maxCounter).map { counter in
                let context = UnloadTokenContextBuilder.freeUnloadTokenContext(period: period, counter: counter)
                return try (period: period, alias: aliasProvider.deriveAlias(for: context))
            }

            let consumed = try await consumedTokenChecker.fetchConsumedStatus(for: queries)
            remaining += consumed.lazy.filter { !$0 }.count
        }

        return UnloadQuota(remaining: remaining, limit: Int(maxCounter) * periods.count)
    }
}
