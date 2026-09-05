import Foundation
import BandersnatchApi
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality
import ExtrinsicService
import StructuredConcurrency
import Operation_iOS
import BigInt
import SDKLogger
import KeyDerivation
import AsyncExtensions
import CommonService
import OperationExt
import os

/// A service that monitors local vouchers and synchronizes their on-chain status.
///
/// This service performs two primary synchronization tasks:
/// 1. **Location Resolution**: For vouchers missing recycler information, it queries the chain to find which
///    recycler and revision the voucher's public key is associated with.
/// 2. **Pending Status Resolution**: For vouchers marked as pending, it monitors the recycler's pending queue.
///    Once the voucher's public key is removed from the chain's pending list, the local record is updated
///    to `isPending = false`.
public final class VoucherLocationService: BaseSyncService {
    private let instanceId: CoinageInstanceId
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let databaseFactory: any DatabaseDependencyFactoring
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let stateLock = OSAllocatedUnfairLock(initialState: SyncStateData())

    private var localVouchersMonitoringTask: Task<Void, Error>?
    private var voucherStatusSubscriptionTask: Task<Void, Error>?

    public init(
        instanceId: CoinageInstanceId,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        databaseFactory: any DatabaseDependencyFactoring,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        logger: any SDKLoggerProtocol
    ) {
        self.instanceId = instanceId
        self.voucherRepository = voucherRepository
        self.databaseFactory = databaseFactory
        self.connection = connection
        self.runtimeService = runtimeService
        super.init(logger: logger)
    }

    deinit {
        stopSyncUp()
    }

    /// Begins monitoring the local database for vouchers not yet in a recycler, resolving their
    /// on-chain location (onboarding → in-recycler) in a single subscription batch.
    override public func performSyncUp() {
        localVouchersMonitoringTask = Task { [weak self] in
            guard let self else { return }

            let stream = databaseFactory.makeTrackedVoucherSnapshotStream()
                .map { $0.map(\.voucher) }
                .map { vouchers in vouchers.filter { !$0.remoteState.isInRecycler } }
                // Resubscribe only when the tracked key-set changes; non-key voucher edits keep the
                // existing subscription.
                .removeDuplicates { previous, current in
                    Set(previous.map(\.publicKey)) == Set(current.map(\.publicKey))
                }

            for try await vouchers in stream {
                guard !vouchers.isEmpty else {
                    logger.debug("Voucher sync stopped")
                    voucherStatusSubscriptionTask?.cancel()
                    continue
                }
                try Task.checkCancellation()

                do {
                    logger.debug("Voucher sync started")
                    try await sync(vouchers)
                } catch {
                    logger.error("Voucher sync failed during monitoring: \(error)")
                }
            }
        }
    }

    override public func stopSyncUp() {
        localVouchersMonitoringTask?.cancel()
        voucherStatusSubscriptionTask?.cancel()
        stateLock.withLock { $0 = SyncStateData() }
    }
}

extension VoucherLocationService {
    /// Generates storage subscription requests for vouchers that are not yet `.inRecycler`.
    /// Subscribes to Members[identifier][voucherPubKey] to detect Onboarding -> Included transitions.
    func memberRequests(_ vouchers: [Voucher]) throws -> [BatchStorageSubscriptionRequest] {
        let pending = vouchers.filter { !$0.remoteState.isInRecycler }

        guard !pending.isEmpty else {
            return []
        }

        return pending.map { voucher in
            let publicKey = voucher.publicKey
            let collectionId = RecyclerCollectionIdentifier.identifier(instanceId: instanceId, for: voucher.exponent)

            let mappingKey = SubscriptionKey.member(
                derivationIndex: voucher.derivationIndex
            ).mappingKey

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.members(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        BytesCodable(wrappedValue: publicKey)
                    )
                }
            )

            return BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey)
        }
    }

    private func ringStatusRequests(snapshot: SyncSnapshot) -> [BatchStorageSubscriptionRequest] {
        var requests: [BatchStorageSubscriptionRequest] = []

        // Transitioning vouchers: ring position accumulated, need ringKeysStatus to confirm ring index.
        for (derivationIndex, ringPosition) in snapshot.accumulatedRingPositions {
            guard let ringIndex = ringPosition.ringIndex,
                  let voucher = snapshot.pendingVouchers.first(where: { $0.derivationIndex == derivationIndex })
            else { continue }

            let collectionId = RecyclerCollectionIdentifier.identifier(instanceId: instanceId, for: voucher.exponent)
            let mappingKey = SubscriptionKey.ringStatus(derivationIndex: derivationIndex).mappingKey

            let innerRequest = DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.ringKeysStatus(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: collectionId),
                        StringCodable(wrappedValue: ringIndex)
                    )
                }
            )

            requests.append(BatchStorageSubscriptionRequest(innerRequest: innerRequest, mappingKey: mappingKey))
        }

        return requests
    }

    /// Orchestrates the blockchain subscription for a set of vouchers.
    /// Cancels existing subscriptions and creates a new batch request for locations and pending
    /// statuses in a single subscription.
    private func sync(_ vouchers: [Voucher]) async throws {
        voucherStatusSubscriptionTask?.cancel()

        let snapshot = stateLock.withLock { state -> SyncSnapshot in
            // Drop accumulated state for vouchers no longer monitored to avoid stale ring status subscriptions.
            let currentIndices = Set(vouchers.map(\.derivationIndex))
            state.accumulatedRingPositions = state.accumulatedRingPositions.filter { currentIndices.contains($0.key) }
            state.accumulatedRingStatuses = state.accumulatedRingStatuses.filter { currentIndices.contains($0.key) }
            state.pendingVouchers = vouchers
            // Reset baseline so the resubscription diff check reflects what this batch actually subscribes to.
            state.subscribedDerivationIndices = Set(state.accumulatedRingPositions.keys)
            return SyncSnapshot(
                pendingVouchers: state.pendingVouchers,
                accumulatedRingPositions: state.accumulatedRingPositions,
                accumulatedRingStatuses: state.accumulatedRingStatuses,
            )
        }

        let memberReqs = try memberRequests(vouchers)
        let allRequests = memberReqs + ringStatusRequests(snapshot: snapshot)

        guard !allRequests.isEmpty else {
            logger.error("Found no subscription requests for non-empty vouchers input")
            return
        }

        voucherStatusSubscriptionTask = Task { [weak self] in
            guard let self else { return }

            let stream: AnyAsyncSequence<MemberStatusResult> = CallbackBatchStorageSubscription
                .asyncStream(
                    requests: allRequests,
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

            for try await result in stream {
                try Task.checkCancellation()
                try await handleSubscriptionUpdate(result)
            }
        }
    }

    /// Processes updates received from the blockchain subscription.
    /// Updates local voucher records if a recycler is found or if a voucher is no longer in the
    /// pending queue.
    private func handleSubscriptionUpdate(
        _ result: MemberStatusResult
    ) async throws {
        let (needsResubscription, snapshot) = stateLock.withLock { state -> (Bool, SyncSnapshot) in
            for update in result.ringPositionUpdates {
                if let position = update.ringPosition, position.isIncluded {
                    state.accumulatedRingPositions[update.derivationIndex] = position
                } else {
                    state.accumulatedRingPositions.removeValue(forKey: update.derivationIndex)
                }
            }
            for update in result.ringStatusUpdates {
                state.accumulatedRingStatuses[update.derivationIndex] = update.ringKeysStatus
            }
            // A new .included position was discovered — its ringKeysStatus subscription must be added to the batch.
            let needsResubscription = Set(state.accumulatedRingPositions.keys) != state.subscribedDerivationIndices
            let snapshot = SyncSnapshot(
                pendingVouchers: state.pendingVouchers,
                accumulatedRingPositions: state.accumulatedRingPositions,
                accumulatedRingStatuses: state.accumulatedRingStatuses
            )
            return (needsResubscription, snapshot)
        }

        if needsResubscription {
            try await sync(snapshot.pendingVouchers)
            return
        }

        let vouchers = try await voucherRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        guard !vouchers.isEmpty else { return }
        let voucherMap = Dictionary(uniqueKeysWithValues: vouchers.map { ($0.derivationIndex, $0) })

        var updates = ringPositionUpdates(from: result.ringPositionUpdates, snapshot: snapshot, voucherMap: voucherMap)
        applyRingStatusUpdates(result.ringStatusUpdates, snapshot: snapshot, voucherMap: voucherMap, into: &updates)

        guard !updates.isEmpty else { return }
        // A dedicated write-only mapper touches only remoteState, so a concurrent change to any other
        // voucher field is not clobbered by this location write.
        let locationUpdates = updates.values.map {
            VoucherLocationUpdate(
                derivationIndex: $0.derivationIndex,
                remoteState: $0.remoteState
            )
        }
        try await databaseFactory.makeVoucherLocationRepository()
            .saveOperation({ locationUpdates }, { [] })
            .asyncExecute()
        logger.debug("Updated \(updates.count) vouchers via subscription")
    }

    private func ringPositionUpdates(
        from memberUpdates: [MemberStatusResult.MemberUpdate],
        snapshot: SyncSnapshot,
        voucherMap: [DerivationIndex: Voucher]
    ) -> [DerivationIndex: Voucher] {
        var updates: [DerivationIndex: Voucher] = [:]

        for update in memberUpdates {
            let derivationIndex = update.derivationIndex
            guard var voucher = updates[derivationIndex] ?? voucherMap[derivationIndex] else { continue }
            var didChange = false

            if let ringPosition = snapshot.accumulatedRingPositions[derivationIndex],
               let ringIndex = ringPosition.ringIndex,
               let ringStatus = snapshot.accumulatedRingStatuses[derivationIndex],
               ringStatus.includesKey(from: ringPosition) {
                let newState = Voucher.OnChainState.inRecycler(
                    Voucher.Recycler(index: ringIndex, membersCount: UInt32(ringStatus.included))
                )
                if voucher.remoteState != newState {
                    voucher = voucher.adjusting(state: newState)
                    didChange = true
                }
            } else if update.ringPosition?.isIncluded == true {
                // Ring position is .included but ringKeysStatus hasn't arrived yet — defer until it does.
                continue
            } else if voucher.remoteState != .onboarding {
                voucher = voucher.adjusting(state: .onboarding)
                didChange = true
            }

            guard didChange else { continue }
            updates[derivationIndex] = voucher
        }

        return updates
    }

    // Second pass: ringKeysStatus arrived in this emission while the ring position was already accumulated
    // from a prior emission. The ring position update loop above won't cover this case.
    private func applyRingStatusUpdates(
        _ ringStatusUpdates: [MemberStatusResult.RingStatusUpdate],
        snapshot: SyncSnapshot,
        voucherMap: [DerivationIndex: Voucher],
        into updates: inout [DerivationIndex: Voucher]
    ) {
        for update in ringStatusUpdates {
            let derivationIndex = update.derivationIndex
            guard let ringStatus = update.ringKeysStatus,
                  var voucher = updates[derivationIndex] ?? voucherMap[derivationIndex] else { continue }
            var didChange = false

            if let ringPosition = snapshot.accumulatedRingPositions[derivationIndex],
               let ringIndex = ringPosition.ringIndex,
               ringStatus.includesKey(from: ringPosition) {
                let newState = Voucher.OnChainState.inRecycler(
                    Voucher.Recycler(index: ringIndex, membersCount: UInt32(ringStatus.included))
                )
                if voucher.remoteState != newState {
                    voucher = voucher.adjusting(state: newState)
                    didChange = true
                }
            }

            guard didChange else { continue }
            updates[derivationIndex] = voucher
        }
    }
}

public extension Voucher.OnChainState {
    var isInRecycler: Bool {
        guard case .inRecycler = self else { return false }
        return true
    }
}

// MARK: Sync state

extension VoucherLocationService {
    private struct SyncStateData {
        var pendingVouchers: [Voucher] = []
        // Tracks which derivation indices have an active ringKeysStatus subscription in the current batch.
        // Compared against discovered ring positions after each emission to detect when resubscription is needed.
        var subscribedDerivationIndices: Set<DerivationIndex> = []
        // Persisted across partial emissions — Substrate subscriptions may deliver position and status in separate
        // batches.
        // Keyed by derivation index
        var accumulatedRingPositions: [DerivationIndex: MembersPallet.RingPosition] = [:]
        var accumulatedRingStatuses: [DerivationIndex: MembersPallet.RingKeysStatus] = [:]
    }

    private struct SyncSnapshot {
        let pendingVouchers: [Voucher]
        let accumulatedRingPositions: [DerivationIndex: MembersPallet.RingPosition]
        let accumulatedRingStatuses: [DerivationIndex: MembersPallet.RingKeysStatus]
    }
}
