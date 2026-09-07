#if TESTNET_FEATURE
    import BigInt
    import Coinage
    import Foundation

    /// Randomised coin/voucher sets for exercising the Coinage UI without real holdings.
    ///
    /// Produced as a ``CoinageHoldings`` snapshot — the same shape the balance service emits — so
    /// fixtures and real data travel one path through the presenter. Regenerated every time the debug
    /// switch is turned on.
    enum CoinageFixtures {
        static let coinCount = 20
        static let voucherCount = 10

        /// Exponent range the fixtures draw from.
        static let minExponent: Int16 = 0
        static let maxExponent: Int16 = 10

        /// Longest provenance chain a fixture coin gets. Draws are biased towards the short end.
        static let maximumHops = 10

        /// Self-contained pricing so test data renders without the chain. Mirrors the live asset:
        /// `unit` is one cent at 18 decimals. Each holding is worth `$0.01 * 2^exponent`.
        static let denominationContext = DenominationBreakdownContext(
            unit: BigUInt(10).power(16),
            precision: 18,
            maxExponent: maxExponent,
            minExponent: minExponent
        )

        static func make() -> CoinageHoldings {
            CoinageHoldings(coins: makeCoins(), vouchers: makeVouchers())
        }
    }

    // MARK: - Coins

    private extension CoinageFixtures {
        /// Public keys are only an identity here, so derive them from the index.
        static func publicKey(for index: Int) -> Data {
            Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        }

        static func makeCoins() -> [CoinageHoldings.CoinHolding] {
            (0 ..< coinCount).map { index in
                let hops = makeHops()

                let coin = Coin(
                    exponent: Int16.random(in: minExponent ... maxExponent),
                    derivationIndex: DerivationIndex(index),
                    age: Int16(hops.count),
                    isOnchain: true,
                    // A fifth carry no known provenance, so the "unknown" depiction gets exercised.
                    recyclerFungibility: Int.random(in: 0 ..< 100) < 20 ? nil : randomFungibility(),
                    hops: hops,
                    publicKey: publicKey(for: index)
                )

                return CoinageHoldings.CoinHolding(coin: coin, isSpendable: .random())
            }
        }

        /// Mostly transfers, with the occasional split. The count is the lower of two draws, which
        /// biases towards short chains while still reaching the cap sometimes.
        static func makeHops() -> [Hop] {
            let count = min(
                Int.random(in: 0 ... maximumHops),
                Int.random(in: 0 ... maximumHops)
            )

            return (0 ..< count).map { _ in
                Int.random(in: 0 ..< 100) < 25
                    ? .split(fanout: UInt8.random(in: 2 ... 7))
                    : .transfer(bundleSize: UInt8.random(in: 1 ... 6))
            }
        }

        /// Biased towards the top of the range so most holdings read as highly fungible.
        static func randomFungibility() -> UInt8 {
            Int.random(in: 0 ..< 100) < 70
                ? UInt8.random(in: 80 ... CoinageConstants.fullFungibility)
                : UInt8.random(in: 0 ..< 80)
        }
    }

    // MARK: - Vouchers

    private extension CoinageFixtures {
        static func makeVouchers() -> [CoinageHoldings.VoucherHolding] {
            let now = Date()

            return (0 ..< voucherCount).map { index in
                let fungibility = randomFungibility()

                let voucher = Voucher(
                    exponent: Int16.random(in: minExponent ... maxExponent),
                    derivationIndex: DerivationIndex(index),
                    allocatedAt: now,
                    readyAt: now,
                    remoteState: .inRecycler(
                        Voucher.Recycler(index: UInt32(index), membersCount: UInt32.random(in: 4 ... 64))
                    ),
                    recyclerFungibility: fungibility,
                    // A ceiling the recycler can still climb to, so never below current.
                    maxRecyclerFungibility: UInt8.random(in: fungibility ... CoinageConstants.fullFungibility),
                    publicKey: publicKey(for: index)
                )

                return CoinageHoldings.VoucherHolding(voucher: voucher, isUnloadable: .random())
            }
        }
    }
#endif
