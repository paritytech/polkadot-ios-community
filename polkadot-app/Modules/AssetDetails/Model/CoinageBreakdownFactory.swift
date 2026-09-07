#if TESTNET_FEATURE
    import BigInt
    import Coinage
    import Foundation

    /// Turns a classified ``CoinageHoldings`` snapshot into what the breakdown draws: the ordered
    /// rows and the summary bar's three shares.
    ///
    /// Pure and free of the presenter's state, so the ordering and the value weighting can be
    /// exercised directly.
    enum CoinageBreakdownFactory {
        /// A row before pricing: what it takes to order it and to draw it.
        struct Row: Equatable {
            let id: String
            let exponent: Int16
            /// Tie-break within one value: spendable coins, then vouchers, then held-back coins.
            let rank: Int
            let derivationIndex: DerivationIndex
            let status: CoinageHoldingViewModel.Status
        }

        /// Coins and vouchers interleaved into one list: by value descending, then by class, then by
        /// derivation index so equal holdings keep a stable order across refreshes.
        static func rows(from holdings: CoinageHoldings) -> [Row] {
            let coinRows = holdings.coins.map { holding in
                Row(
                    id: "coin-\(holding.coin.derivationIndex)",
                    exponent: holding.coin.exponent,
                    rank: holding.isSpendable ? 0 : 2,
                    derivationIndex: holding.coin.derivationIndex,
                    status: .coin(
                        CoinStatusView.Model(
                            hopDots: holding.coin.hops.map(innerDots(for:)),
                            fungibility: holding.coin.recyclerFungibility,
                            isSpendable: holding.isSpendable
                        )
                    )
                )
            }

            let voucherRows = holdings.vouchers.map { holding in
                Row(
                    id: "voucher-\(holding.voucher.derivationIndex)",
                    exponent: holding.voucher.exponent,
                    rank: 1,
                    derivationIndex: holding.voucher.derivationIndex,
                    status: .voucher(
                        VoucherStatusView.Model(
                            maxFungibility: holding.voucher.maxRecyclerFungibility,
                            fungibility: holding.voucher.recyclerFungibility,
                            isUnloadable: holding.isUnloadable
                        )
                    )
                )
            }

            // Value is `unit * 2^exponent`, so ordering by exponent is exactly ordering by value.
            return (coinRows + voucherRows).sorted { lhs, rhs in
                if lhs.exponent != rhs.exponent {
                    return lhs.exponent > rhs.exponent
                }

                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }

                return lhs.derivationIndex < rhs.derivationIndex
            }
        }

        /// Value-weighted split for the summary bar: spendable coins, everything in a recycler, and
        /// coins the strategy will not release. Every holding lands in exactly one section, so the
        /// three shares account for the whole total balance.
        static func composition(
            of holdings: CoinageHoldings,
            context: DenominationBreakdownContext
        ) -> CoinageCompositionBar.Model {
            var spendable = BigUInt(0)
            var loading = BigUInt(0)
            var unspendable = BigUInt(0)

            for holding in holdings.coins {
                let value = context.valueInPlanks(for: holding.coin.exponent)

                if holding.isSpendable {
                    spendable += value
                } else {
                    unspendable += value
                }
            }

            for holding in holdings.vouchers {
                loading += context.valueInPlanks(for: holding.voucher.exponent)
            }

            let total = spendable + loading + unspendable

            guard total > 0 else { return .empty }

            // Scaled integer division keeps this exact for plank counts far beyond Double.
            func share(_ part: BigUInt) -> Double {
                let scale = BigUInt(1_000_000)
                return Double(part * scale / total) / Double(scale)
            }

            return CoinageCompositionBar.Model(
                spendableShare: share(spendable),
                loadingShare: share(loading),
                unspendableShare: share(unspendable)
            )
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

    /// The three figures shown above the summary bar.
    struct CoinageAmounts: Equatable {
        let total: Decimal
        let spendable: Decimal
        let pending: Decimal
    }
#endif
