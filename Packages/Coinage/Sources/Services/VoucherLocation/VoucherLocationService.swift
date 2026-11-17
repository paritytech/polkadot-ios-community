import Foundation
import BandersnatchApi
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality
import StructuredConcurrency
import Operation_iOS
import SDKLogger
import AsyncExtensions
import CommonService
import OperationExt

/// A service that monitors local vouchers and synchronizes their on-chain status.
///
/// Tracks every voucher the durability layer still cares about (`shouldTrackOnchain` — not spent, not
/// mint-failed), not just those outside a recycler: a ring keeps filling after a voucher lands in it, and
/// the member count is what the strategies read to decide when it may be spent. Two-phase per batch, held
/// together entirely by stream operators rather than in-memory
/// reconciliation:
/// 1. **Members**: subscribe `Members[collection][voucherPubKey]` for every voucher and `scan` the
///    per-key deltas into a complete positions snapshot.
/// 2. **RingKeysStatus + RecyclersUnloadedCount + RecyclerAliasStates**: `flatMapLatest` re-derives the
///    ring-state subscription from the current positions and `scan`s its deltas into complete snapshots,
///    then joins them into the resolved location — onboarding, in-recycler(ringIndex, ringMembers), or
///    unloaded when the voucher's alias proves it spent — together with the ring's fungibility, which is a
///    function of those readings and the ring capacity.
public final class VoucherLocationService: BaseSyncService {
    let instanceId: CoinageInstanceId
    private let databaseFactory: any DatabaseDependencyFactoring
    private let chainReader: any VoucherLocationChainReading
    private let ringCapacityProvider: any RingCapacityProviding
    private let aliasProvider: (CoinageKeyIndex) throws -> Data

    private var localVouchersMonitoringTask: Task<Void, Error>?
    private var voucherStatusSubscriptionTask: Task<Void, Error>?

    init(
        instanceId: CoinageInstanceId,
        databaseFactory: any DatabaseDependencyFactoring,
        chainReader: any VoucherLocationChainReading,
        ringCapacityProvider: any RingCapacityProviding,
        aliasProvider: @escaping (CoinageKeyIndex) throws -> Data,
        logger: any SDKLoggerProtocol
    ) {
        self.instanceId = instanceId
        self.databaseFactory = databaseFactory
        self.chainReader = chainReader
        self.ringCapacityProvider = ringCapacityProvider
        self.aliasProvider = aliasProvider
        super.init(logger: logger)
    }

    deinit {
        stopSyncUp()
    }

    /// Begins monitoring the local database for vouchers worth tracking on chain (`shouldTrackOnchain`),
    /// resolving their location (onboarding → in-recycler → unloaded) and refreshing the ring member count.
    override public func performSyncUp() {
        localVouchersMonitoringTask = Task { [weak self] in
            guard let self else { return }

            let stream = databaseFactory.makeTrackedVoucherSnapshotStream()
                .map { TrackedSet($0.filter(\.shouldTrackOnchain)) }
                // A restore clears enteredAt; resubscribe so its next confirmation starts a new timer. A
                // payment starting or settling changes which vouchers may be judged from their alias.
                .removeDuplicates { $0.fingerprint == $1.fingerprint }

            for try await tracked in stream {
                voucherStatusSubscriptionTask?.cancel()

                guard !tracked.vouchers.isEmpty else {
                    logger.debug("Voucher sync stopped")
                    continue
                }
                try Task.checkCancellation()

                logger.debug("Voucher sync started: \(tracked.vouchers.count)")
                startLocationSync(for: tracked)
            }
        }
    }

    override public func stopSyncUp() {
        localVouchersMonitoringTask?.cancel()
        voucherStatusSubscriptionTask?.cancel()
    }
}

// MARK: - Tracked set

extension VoucherLocationService {
    /// The vouchers one pipeline run subscribes, and which of them may be judged spent from their alias.
    struct TrackedSet {
        struct Fingerprint: Equatable {
            let enteredAt: Date?
            let aliasEligible: Bool
        }

        let vouchers: [Voucher]
        let aliasEligible: Set<CoinageKeyIndex>

        init(_ tracked: [TrackedVoucher]) {
            vouchers = tracked.map(\.voucher)
            aliasEligible = Set(tracked.filter(\.isAliasEligible).map(\.voucher.derivationIndex))
        }

        var fingerprint: [PublicKey: Fingerprint] {
            Dictionary(
                vouchers.map {
                    ($0.publicKey, Fingerprint(
                        enteredAt: $0.recycler?.enteredAt,
                        aliasEligible: aliasEligible.contains($0.derivationIndex)
                    ))
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
}

extension VoucherLocationService {
    private func startLocationSync(for tracked: TrackedSet) {
        voucherStatusSubscriptionTask = Task { [weak self] in
            do {
                try await self?.runLocationPipeline(for: tracked)
            } catch {
                // Superseded by a newer tracked-voucher set: whatever the pipeline threw on the way out,
                // an operation cancelled underneath it included, is not a failure.
                guard !Task.isCancelled else { return }
                self?.logger.error("Voucher sync failed during monitoring: \(error)")
            }
        }
    }

    /// The reactive two-phase pipeline. `scan` keeps a complete positions snapshot up to date from the
    /// member subscription's deltas; `flatMapLatest` re-derives the ring-status subscription whenever the
    /// positions change and `scan`s its deltas into a complete status snapshot. Joining the two is a pure
    /// function, so nothing needs to be reconciled by hand between emissions.
    private func runLocationPipeline(for tracked: TrackedSet) async throws {
        let vouchers = tracked.vouchers
        let memberReqs = try memberRequests(vouchers)
        guard !memberReqs.isEmpty else { return }

        // A runtime constant rather than storage, so it is read once per subscription, not per emission.
        let keysPerPage = try await chainReader.ringKeysPageSize()

        // Ring capacity is chain config keyed by denomination and cannot change within a session, so
        // it is resolved once per tracked set rather than per emission. A denomination that fails to
        // resolve simply has no fungibility written until it does.
        let capacities = try await ringCapacityProvider.capacities(
            for: Set(vouchers.map(\.exponent))
        )

        // Derived once per run rather than per position change: one key-manager walk per voucher.
        let aliases = aliases(for: tracked)

        let resolvedStream = positionsStream(requests: memberReqs, vouchers: vouchers)
            .flatMapLatest { [weak self] positions -> AnyAsyncSequence<[CoinageKeyIndex: VoucherLocationUpdate]> in
                guard let self else {
                    return AsyncEmptySequence().eraseToAnyAsyncSequence()
                }
                return resolvedLocationsStream(
                    positions: positions,
                    vouchers: vouchers,
                    aliases: aliases,
                    capacities: capacities,
                    keysPerPage: keysPerPage
                )
            }
            .removeDuplicates { $0 == $1 }

        for try await updates in resolvedStream {
            try Task.checkCancellation()
            try await write(updates)
        }
    }

    /// Phase 1: `scan`s the member subscription's deltas into a complete positions snapshot.
    private func positionsStream(
        requests: [BatchStorageSubscriptionRequest],
        vouchers: [Voucher]
    ) -> AnyAsyncSequence<[CoinageKeyIndex: UncertainStorage<MembersPallet.RingPosition?>]> {
        // Member updates arrive keyed by the voucher's public key, the way they were subscribed.
        let indexByPublicKey = Dictionary(
            vouchers.map { ($0.publicKey, $0.derivationIndex) },
            uniquingKeysWith: { first, _ in first }
        )

        return chainReader.subscribe(requests)
            .scan([CoinageKeyIndex: UncertainStorage<MembersPallet.RingPosition?>]()) { positions, result in
                var positions = positions
                for update in result.ringPositionUpdates {
                    guard let index = indexByPublicKey[update.publicKey] else { continue }
                    // The update was delivered, so it is `.defined`; a delivered empty reading is
                    // `.defined(nil)` (retraction) rather than a dropped key, so it can revert the voucher.
                    // A key never delivered stays absent — that, not `.undefined`, is "not changed".
                    positions[index] = .defined(update.ringPosition)
                }
                return positions
            }
            .eraseToAnyAsyncSequence()
    }

    /// Subscribes to the ring readings and alias rows the current positions call for, `scan`s the deltas
    /// into a complete snapshot, and resolves each voucher's location against it. When no voucher is yet
    /// placed in a ring, emits the onboarding-only resolution once so those writes still happen.
    private func resolvedLocationsStream(
        positions: [CoinageKeyIndex: UncertainStorage<MembersPallet.RingPosition?>],
        vouchers: [Voucher],
        aliases: [CoinageKeyIndex: Data],
        capacities: [Int16: Int],
        keysPerPage: Int
    ) -> AnyAsyncSequence<[CoinageKeyIndex: VoucherLocationUpdate]> {
        let voucherByIndex = Dictionary(uniqueKeysWithValues: vouchers.map { ($0.derivationIndex, $0) })
        let recyclers = Self.recyclers(positions: positions, voucherByIndex: voucherByIndex)
        let requests = ringRequests(for: recyclers, aliases: aliases)

        guard !requests.isEmpty else {
            let resolved = Self.resolveLocations(
                positions: positions,
                statuses: [:],
                aliasStates: [:],
                keysPerPage: keysPerPage
            )
            return AsyncJustSequence(Self.updates(
                locations: resolved,
                unloadedCounts: [:],
                voucherByIndex: voucherByIndex,
                capacities: capacities
            )).eraseToAnyAsyncSequence()
        }

        return chainReader.subscribe(requests)
            .scan(RingSnapshot.empty) { snapshot, result in
                snapshot.applying(result)
            }
            .map { snapshot in
                // The ring readings are shared per ring; the resolution below is per voucher, so each
                // voucher reads the ring it sits in. Alias rows are per voucher already.
                let statuses = recyclers.compactMapValues { snapshot.statuses[$0] }
                let unloadedCounts = recyclers.compactMapValues { snapshot.unloadedCounts[$0] }

                return Self.updates(
                    locations: Self.resolveLocations(
                        positions: positions,
                        statuses: statuses,
                        aliasStates: snapshot.aliasStates,
                        keysPerPage: keysPerPage
                    ),
                    unloadedCounts: unloadedCounts,
                    voucherByIndex: voucherByIndex,
                    capacities: capacities
                )
            }
            .eraseToAnyAsyncSequence()
    }

    /// Aliases of the vouchers that may be judged from them. A derivation that fails leaves that voucher
    /// without an alias row — resolved from its position alone — rather than failing the run.
    private func aliases(for tracked: TrackedSet) -> [CoinageKeyIndex: Data] {
        tracked.aliasEligible.reduce(into: [:]) { aliases, index in
            do {
                aliases[index] = try aliasProvider(index)
            } catch {
                logger.error("Voucher alias derivation failed for \(index): \(error)")
            }
        }
    }
}

// MARK: - Persistence

private extension VoucherLocationService {
    func write(_ updates: [CoinageKeyIndex: VoucherLocationUpdate]) async throws {
        guard !updates.isEmpty else { return }

        // A dedicated write-only mapper touches only the location and fungibility columns, so a
        // concurrent change to any other voucher field is not clobbered by this write.
        let values = Array(updates.values)

        try await databaseFactory.makeVoucherLocationRepository()
            .saveOperation({ values }, { [] })
            .asyncExecute()
        logger.debug("Updated \(values.count) voucher locations via subscription")
    }
}
