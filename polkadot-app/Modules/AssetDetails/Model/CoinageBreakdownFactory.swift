import BigInt
import Coinage
import Foundation

/// Turns a classified ``CoinageHoldings`` snapshot into what the breakdown draws: the ordered
/// rows and the summary bar's three shares.
///
/// Pure and free of the presenter's state, so the ordering and the value weighting can be
/// exercised directly.
enum CoinageBreakdownFactory {
    /// Which half of the list a row belongs to. Holdings whose recycler we have no record of are
    /// the least fungible thing we can say anything about, so they lead.
    enum Standing: Int, Equatable {
        case unknownHistory = 0
        case knownLevel = 1
    }

    /// A row before pricing: what it takes to order it and to draw it.
    struct Row: Equatable {
        let id: String
        let exponent: Int16
        let standing: Standing
        /// Descending within a standing: hop count for ``Standing/unknownHistory``, fungibility
        /// bucket for ``Standing/knownLevel``. Both read "least fungible first".
        let severity: Int
        let derivationIndex: DerivationIndex
        let status: CoinageHoldingStatus
    }

    /// One list, ordered least fungible first: unknown histories lead, deepest first, then
    /// everything whose level we know, by bucket. Value breaks ties, then derivation index so
    /// equal holdings keep a stable order across refreshes.
    static func rows(from holdings: CoinageHoldings) -> [Row] {
        let coinRows = holdings.coins.map { holding in
            let bucket = bucket(for: holding.coin)

            return Row(
                id: "coin-\(holding.coin.derivationIndex)",
                exponent: holding.coin.exponent,
                standing: bucket == nil ? .unknownHistory : .knownLevel,
                severity: bucket ?? holding.coin.hops.count,
                derivationIndex: holding.coin.derivationIndex,
                status: .coin(
                    CoinStatusView.Model(
                        hopDots: holding.coin.hops.map(innerDots(for:)),
                        bucket: bucket,
                        isSpendable: holding.isAvailableNow
                    )
                )
            )
        }

        let voucherRows = holdings.vouchers.map { holding in
            let bucket = CoinageStatusMetrics.bucket(forScore: holding.voucher.recyclerFungibility)

            return Row(
                id: "voucher-\(holding.voucher.derivationIndex)",
                exponent: holding.voucher.exponent,
                standing: .knownLevel,
                severity: bucket,
                derivationIndex: holding.voucher.derivationIndex,
                status: .voucher(
                    VoucherStatusView.Model(
                        maxBucket: CoinageStatusMetrics.bucket(
                            forScore: holding.voucher.maxRecyclerFungibility
                        ),
                        bucket: bucket,
                        isUnloadable: holding.isAvailableNow
                    )
                )
            )
        }

        // Value is `unit * 2^exponent`, so ordering by exponent is exactly ordering by value.
        return (coinRows + voucherRows).sorted { lhs, rhs in
            if lhs.standing != rhs.standing {
                return lhs.standing.rawValue < rhs.standing.rawValue
            }

            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }

            if lhs.exponent != rhs.exponent {
                return lhs.exponent > rhs.exponent
            }

            return lhs.derivationIndex < rhs.derivationIndex
        }
    }

    /// One depiction and the holdings that share it.
    struct Group: Equatable {
        let id: String
        let status: CoinageHoldingStatus
        /// Exponents in display order, one per holding, so a caller can price them and total them.
        let exponents: [Int16]
    }

    /// Folds runs of identical depictions. Rows arrive ordered, so anything that draws the same is
    /// already adjacent and this is a scan. Two rows merge exactly when their status compares
    /// equal, which is the condition under which they would otherwise draw the same row twice.
    static func group(_ rows: [Row]) -> [Group] {
        rows.reduce(into: [Group]()) { groups, row in
            if let last = groups.last, last.status == row.status {
                groups[groups.count - 1] = Group(
                    id: last.id,
                    status: last.status,
                    exponents: last.exponents + [row.exponent]
                )
            } else {
                groups.append(Group(id: row.id, status: row.status, exponents: [row.exponent]))
            }
        }
    }

    /// The bucket a coin's bar is drawn at, or `nil` when we have no record of its recycler.
    ///
    /// A coin that left in a batch is linked to everything that left with it, which the recycler's
    /// own score knows nothing about, so it is pushed down the ladder. The batch is not recorded,
    /// but it is identifiable: the chain only hands out age 1 on a batch unload, and a single
    /// unload leaves age 0.
    static func bucket(for coin: Coin) -> Int? {
        guard let fungibility = coin.recyclerFungibility else { return nil }

        let base = CoinageStatusMetrics.bucket(forScore: fungibility)

        guard coin.hops.isEmpty, coin.age == 1 else { return base }

        return min(base + CoinageStatusMetrics.batchUnloadPenalty, CoinageStatusMetrics.maximumBucket)
    }

    /// Value-weighted split for the summary bar, bucketed exactly as the figures above it are:
    /// every holding lands in one bucket regardless of whether it is a coin or a voucher, so the
    /// three shares account for the whole total balance.
    static func composition(
        of holdings: CoinageHoldings,
        context: DenominationBreakdownContext
    ) -> CoinageCompositionBar.Model {
        let planks = planksByAvailability(of: holdings) {
            context.valueInPlanks(for: $0)
        }
        let total = planks.total

        guard total > 0 else { return .empty }

        // Scaled integer division keeps this exact for plank counts far beyond Double.
        func share(_ part: BigUInt) -> Double {
            let scale = BigUInt(1_000_000)
            return Double(part * scale / total) / Double(scale)
        }

        return CoinageCompositionBar.Model(
            availableNowShare: share(planks.availableNow),
            gainingPrivacyShare: share(planks.gainingPrivacy),
            pendingShare: share(planks.pending)
        )
    }

    /// Plank totals per bucket. A named type rather than a tuple, so the three stay labelled
    /// wherever they travel.
    private struct BucketPlanks {
        var availableNow = BigUInt(0)
        var gainingPrivacy = BigUInt(0)
        var pending = BigUInt(0)

        var total: BigUInt { availableNow + gainingPrivacy + pending }
    }

    private static func planksByAvailability(
        of holdings: CoinageHoldings,
        value: (Int16) -> BigUInt
    ) -> BucketPlanks {
        var planks = BucketPlanks()

        func add(_ availability: CoinageAvailability, _ amount: BigUInt) {
            switch availability {
            case .availableNow: planks.availableNow += amount
            case .gainingPrivacy: planks.gainingPrivacy += amount
            case .pending: planks.pending += amount
            }
        }

        for holding in holdings.coins {
            add(holding.availability, value(holding.coin.exponent))
        }

        for holding in holdings.vouchers {
            add(holding.availability, value(holding.voucher.exponent))
        }

        return planks
    }

    /// Inner dots for a hop: one per sibling it moved or was produced alongside.
    private static func innerDots(for hop: Hop) -> Int {
        switch hop {
        case let .transfer(bundleSize):
            CoinageStatusMetrics.innerDots(forCount: bundleSize)
        case let .split(fanout):
            CoinageStatusMetrics.innerDots(forCount: fanout)
        }
    }
}

/// The figures shown above the summary bar. The last three partition ``total``, and are the
/// three buckets the bar draws.
struct CoinageAmounts: Equatable {
    let total: Decimal
    let availableNow: Decimal
    let gainingPrivacy: Decimal
    let pending: Decimal

    static let zero = CoinageAmounts(total: 0, availableNow: 0, gainingPrivacy: 0, pending: 0)
}
