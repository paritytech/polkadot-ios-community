import Foundation
import Foundation_iOS
import Individuality

/// The pure half of the location pipeline: the snapshots the subscriptions accumulate and the join that
/// turns them into the location each voucher should be persisted with.
extension VoucherLocationService {
    /// The ring each placed voucher sits in. Vouchers that share a ring map to one ``RecyclerKey``,
    /// which is what collapses their subscriptions into a single request each.
    static func recyclers(
        positions: [CoinageKeyIndex: UncertainStorage<MembersPallet.RingPosition?>],
        voucherByIndex: [CoinageKeyIndex: Voucher]
    ) -> [CoinageKeyIndex: RecyclerKey] {
        positions.reduce(into: [:]) { recyclers, entry in
            guard case let .defined(.some(position)) = entry.value,
                  let ringIndex = position.ringIndex,
                  let voucher = voucherByIndex[entry.key]
            else { return }

            recyclers[entry.key] = RecyclerKey(exponent: voucher.exponent, index: ringIndex)
        }
    }

    /// The per-ring readings and per-voucher alias rows, accumulated from the subscription's deltas.
    /// Kept together so one `scan` covers all three and the join sees a consistent set.
    struct RingSnapshot {
        var statuses: [RecyclerKey: UncertainStorage<MembersPallet.RingKeysStatus?>]
        var unloadedCounts: [RecyclerKey: UncertainStorage<UInt32?>]
        var aliasStates: [CoinageKeyIndex: UncertainStorage<CoinagePallet.AliasState?>]

        static let empty = RingSnapshot(statuses: [:], unloadedCounts: [:], aliasStates: [:])

        func applying(_ result: MemberStatusResult) -> RingSnapshot {
            var snapshot = self

            for update in result.ringStatusUpdates {
                snapshot.statuses[update.recycler] = .defined(update.ringKeysStatus)
            }

            for update in result.unloadedCountUpdates {
                snapshot.unloadedCounts[update.recycler] = .defined(update.unloadedCount)
            }

            for update in result.aliasUpdates {
                snapshot.aliasStates[update.index] = .defined(update.aliasState)
            }

            return snapshot
        }
    }
}

// MARK: - Resolution

extension VoucherLocationService {
    /// Pure join of the snapshots into the location each voucher should be persisted with.
    ///
    /// The snapshots are read three ways: a key absent from the map (or ``UncertainStorage/undefined``) was
    /// not delivered in the subscription and is left untouched; a ``UncertainStorage/defined(_:)`` with a
    /// `nil` reading was delivered empty (absent on chain or retracted by a fork); and a `.defined` with a
    /// value carries it.
    ///
    /// - An alias delivered `.unloaded` is the only proof a voucher is spent and outranks its position:
    ///   the voucher becomes `.unloaded`. Any other alias reading (absent, locked, not delivered) leaves
    ///   the position to decide, which is also how a fork that retracts the unload brings it back.
    /// - A member row delivered empty (`.defined(nil)`, retracted) reverts the voucher to `.unlocated` — the
    ///   fix for the case a fork drops a member and the stale in-recycler state would otherwise linger.
    /// - An included voucher whose ring status confirms its key becomes in-recycler with the real member
    ///   count; if that ring status is delivered empty (the ring was retracted) the voucher falls back to
    ///   onboarding.
    /// - A status not delivered yet leaves the voucher deferred (no entry emitted) rather than guessed at.
    /// - Anything else (onboarding/suspended position) is onboarding.
    static func resolveLocations(
        positions: [CoinageKeyIndex: UncertainStorage<MembersPallet.RingPosition?>],
        statuses: [CoinageKeyIndex: UncertainStorage<MembersPallet.RingKeysStatus?>],
        aliasStates: [CoinageKeyIndex: UncertainStorage<CoinagePallet.AliasState?>],
        keysPerPage: Int,
        observedAt: Date = .now
    ) -> [CoinageKeyIndex: Voucher.OnChainState] {
        positions.reduce(into: [:]) { resolved, entry in
            let (derivationIndex, positionEntry) = entry

            if case .defined(.some(.unloaded))? = aliasStates[derivationIndex] {
                resolved[derivationIndex] = .unloaded
                return
            }

            // Not delivered — leave the voucher as it is.
            guard case let .defined(deliveredPosition) = positionEntry else { return }

            // Delivered empty — the member row was retracted; revert to unlocated.
            guard let position = deliveredPosition else {
                resolved[derivationIndex] = .unlocated
                return
            }

            guard let ringIndex = position.ringIndex else {
                resolved[derivationIndex] = .onboarding
                return
            }

            switch statuses[derivationIndex] {
            case .none,
                 .undefined?:
                // Ring status not delivered yet — defer rather than guess.
                return
            case .defined(.none)?:
                // The ring status was delivered empty (ring retracted): fall back to onboarding.
                resolved[derivationIndex] = .onboarding
            case let .defined(.some(status))?:
                guard status.includesKey(from: position, keysPerPage: keysPerPage) else { return }
                resolved[derivationIndex] = .inRecycler(
                    Voucher.Recycler(index: ringIndex, membersCount: status.included, enteredAt: observedAt)
                )
            }
        }
    }
}

extension VoucherLocationService {
    /// Pairs each resolved location with its ring's fungibility.
    ///
    /// A score is only attached when the ring's own readings are all in hand: the voucher resolved
    /// into a ring, its unloaded count was actually delivered, and its denomination's capacity is
    /// known. Anything short of that leaves the stored score alone rather than guessing an
    /// optimistic one — this drives a privacy indicator, so an absent reading must not read as
    /// "nothing unloaded".
    static func updates(
        locations: [CoinageKeyIndex: Voucher.OnChainState],
        unloadedCounts: [CoinageKeyIndex: UncertainStorage<UInt32?>],
        voucherByIndex: [CoinageKeyIndex: Voucher],
        capacities: [Int16: Int]
    ) -> [CoinageKeyIndex: VoucherLocationUpdate] {
        locations.reduce(into: [:]) { updates, entry in
            let (derivationIndex, location) = entry

            updates[derivationIndex] = VoucherLocationUpdate(
                derivationIndex: derivationIndex,
                remoteState: location,
                recyclerFungibility: nil,
                maxRecyclerFungibility: nil
            )

            guard case let .inRecycler(recycler) = location,
                  // Delivered-and-absent is a real zero: the pallet creates the entry on the first
                  // unload, so "no entry" means nothing has been unloaded from this ring yet.
                  case let .defined(delivered) = unloadedCounts[derivationIndex] ?? .undefined,
                  let exponent = voucherByIndex[derivationIndex]?.exponent,
                  let capacity = capacities[exponent]
            else { return }

            let unloaded = delivered ?? 0

            updates[derivationIndex] = VoucherLocationUpdate(
                derivationIndex: derivationIndex,
                remoteState: location,
                recyclerFungibility: RecyclerFungibility.current(
                    included: recycler.membersCount,
                    unloaded: unloaded,
                    capacity: capacity
                ),
                maxRecyclerFungibility: RecyclerFungibility.maximum(
                    included: recycler.membersCount,
                    unloaded: unloaded,
                    capacity: capacity
                )
            )
        }
    }
}
