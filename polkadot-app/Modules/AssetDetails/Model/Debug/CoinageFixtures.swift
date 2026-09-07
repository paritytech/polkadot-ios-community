#if TESTNET_FEATURE
    import BigInt
    import Coinage
    import Foundation

    /// Hardcoded coin/voucher sets for exercising the Coinage UI without real holdings.
    ///
    /// Produced as `TrackedCoin`/`TrackedVoucher` so fixtures travel the same path as real
    /// holdings, including the domain's `isBalanceCounted` inclusion rule. Regenerated every
    /// time the debug switch is turned on, so voucher timestamps stay relative to that moment.
    enum CoinageFixtures {
        static let coinCount = 15
        static let voucherCount = 10

        /// Exponent range the fixtures draw from.
        static let minExponent: Int16 = 0
        static let maxExponent: Int16 = 10

        /// Self-contained pricing so test data renders without the chain. Mirrors the live
        /// asset: `unit` is one cent at 18 decimals, matching the note on
        /// `DenominationBreakdownContext`. Each holding is worth `$0.01 * 2^exponent`.
        static let denominationContext = DenominationBreakdownContext(
            unit: BigUInt(10).power(16),
            precision: 18,
            maxExponent: maxExponent,
            minExponent: minExponent
        )

        static func make(referenceDate: Date = .now) -> (coins: [TrackedCoin], vouchers: [TrackedVoucher]) {
            (coins: makeCoins(), vouchers: makeVouchers(referenceDate: referenceDate))
        }
    }

    // MARK: - Coins

    private extension CoinageFixtures {
        /// Unclaimed, present on chain: the state that makes a holding count towards the balance.
        static var freeState: CoinageAssetState {
            CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)
        }

        /// Public keys are only an identity here, so derive them from the index.
        static func publicKey(for index: Int) -> Data {
            Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        }

        static func makeCoins() -> [TrackedCoin] {
            (0 ..< coinCount).map { index in
                let age = Int16.random(in: 0 ... 10)

                let coin = Coin(
                    exponent: Int16.random(in: minExponent ... maxExponent),
                    derivationIndex: DerivationIndex(index),
                    age: age,
                    isOnchain: true,
                    recyclerFungibility: randomFungibility(),
                    hops: makeHops(count: Int(age)),
                    publicKey: publicKey(for: index)
                )

                return TrackedCoin(coin: coin, state: freeState)
            }
        }

        /// One hop per unit of age: mostly transfers, with the occasional split.
        static func makeHops(count: Int) -> [Hop] {
            (0 ..< count).map { _ in
                Int.random(in: 0 ..< 100) < 20
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
        static let minimumReadyDelay: TimeInterval = 5 * 60
        static let allocationWindow: TimeInterval = 60 * 60

        static func makeVouchers(referenceDate now: Date) -> [TrackedVoucher] {
            (0 ..< voucherCount).map { index in
                let allocatedAt = now.addingTimeInterval(-TimeInterval.random(in: 0 ... allocationWindow))
                let fungibility = randomFungibility()

                let voucher = Voucher(
                    exponent: Int16.random(in: minExponent ... maxExponent),
                    derivationIndex: DerivationIndex(index),
                    allocatedAt: allocatedAt,
                    readyAt: makeReadyAt(allocatedAt: allocatedAt, now: now),
                    remoteState: .inRecycler(
                        Voucher.Recycler(index: UInt32(index), membersCount: UInt32.random(in: 4 ... 64))
                    ),
                    recyclerFungibility: fungibility,
                    // A ceiling the recycler can still climb to, so never below current.
                    maxRecyclerFungibility: UInt8.random(in: fungibility ... CoinageConstants.fullFungibility),
                    publicKey: publicKey(for: index)
                )

                return TrackedVoucher(voucher: voucher, state: freeState)
            }
        }

        /// Aims for 30% already-ready vouchers, but the "at least 5 minutes after allocation"
        /// invariant wins: a voucher allocated less than 5 minutes ago cannot be ready yet.
        static func makeReadyAt(allocatedAt: Date, now: Date) -> Date {
            let earliest = allocatedAt.addingTimeInterval(minimumReadyDelay)
            let wantsPast = Int.random(in: 0 ..< 100) < 30

            guard wantsPast, earliest < now else {
                return max(earliest, now.addingTimeInterval(.random(in: 60 ... 2 * allocationWindow)))
            }

            return Date(
                timeIntervalSince1970: .random(
                    in: earliest.timeIntervalSince1970 ... now.timeIntervalSince1970
                )
            )
        }
    }
#endif
