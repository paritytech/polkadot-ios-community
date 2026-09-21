import Coinage
import Foundation
import Testing
@testable import polkadot_app

/// The fungibility ladder and the order it puts the breakdown rows in.
@Suite("Coinage breakdown ordering")
struct CoinageBreakdownOrderTests {
    // MARK: - The ladder

    @Test("Full fungibility is the shortest bar, none is the longest")
    func ladderEnds() {
        #expect(CoinageStatusMetrics.bucket(forScore: 100) == 0)
        #expect(CoinageStatusMetrics.bucket(forScore: 0) == CoinageStatusMetrics.maximumBucket)
        #expect(CoinageStatusMetrics.fraction(forBucket: 0) == 0)
        #expect(CoinageStatusMetrics.fraction(forBucket: CoinageStatusMetrics.maximumBucket) == 1)
    }

    @Test("Buckets widen as fungibility falls", arguments: [
        (100, 0), (66, 0), (65, 1), (43, 1), (42, 2), (28, 2),
        (27, 3), (19, 3), (18, 4), (12, 4), (11, 5), (8, 5),
        (7, 6), (5, 6), (4, 7), (2, 7), (1, 8), (0, 8)
    ])
    func ladder(score: Int, expected: Int) {
        #expect(CoinageStatusMetrics.bucket(forScore: UInt8(score)) == expected)
    }

    @Test("Every score lands in exactly one bucket, and the ladder never reverses")
    func ladderIsMonotonic() {
        let buckets = (0 ... 100).map { CoinageStatusMetrics.bucket(forScore: UInt8($0)) }

        #expect(Set(buckets) == Set(0 ... CoinageStatusMetrics.maximumBucket))
        #expect(buckets == buckets.sorted().reversed())
    }

    // MARK: - The batch penalty

    @Test("A single unload is scored on its recycler alone")
    func singleUnloadHasNoPenalty() {
        let coin = coin(age: 0, fungibility: 12)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == 4)
    }

    @Test("A batch unload is pushed down the ladder")
    func batchUnloadIsPenalised() {
        let coin = coin(age: 1, fungibility: 12)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == 4 + CoinageStatusMetrics.batchUnloadPenalty)
    }

    @Test("The penalty cannot push a coin past the end of the ladder")
    func penaltyClamps() {
        let coin = coin(age: 1, fungibility: 0)

        #expect(CoinageBreakdownFactory.bucket(for: coin) == CoinageStatusMetrics.maximumBucket)
    }

    @Test("A coin with no recycler record has no bucket")
    func unknownHistoryHasNoBucket() {
        let coin = coin(age: 3, fungibility: nil, hops: [.transfer(bundleSize: 4)])

        #expect(CoinageBreakdownFactory.bucket(for: coin) == nil)
    }

    // MARK: - The order

    @Test("Unknown histories lead, deepest first, then known levels least fungible first")
    func order() {
        let holdings = CoinageHoldings(
            coins: [
                holding(coin(age: 2, fungibility: nil, hops: hops(2))),
                holding(coin(age: 5, fungibility: nil, hops: hops(5))),
                holding(coin(age: 0, fungibility: 100)),
                holding(coin(age: 0, fungibility: 20))
            ],
            vouchers: [holding(voucher(fungibility: 50))]
        )

        let expected: [Placement] = [
            .unknownHistory(5),
            .unknownHistory(2),
            .knownLevel(3),
            .knownLevel(1),
            .knownLevel(0)
        ]

        #expect(severities(of: holdings) == expected)
    }

    @Test("Value breaks ties within one bucket, largest first")
    func valueBreaksTies() {
        let holdings = CoinageHoldings(
            coins: [
                holding(coin(exponent: 3, age: 0, fungibility: 20)),
                holding(coin(exponent: 9, age: 0, fungibility: 20)),
                holding(coin(exponent: 6, age: 0, fungibility: 20))
            ],
            vouchers: []
        )

        #expect(CoinageBreakdownFactory.rows(from: holdings).map(\.exponent) == [9, 6, 3])
    }
}

// MARK: - Fixtures

private extension CoinageBreakdownOrderTests {
    enum Placement: Equatable {
        case unknownHistory(Int)
        case knownLevel(Int)
    }

    func severities(of holdings: CoinageHoldings) -> [Placement] {
        CoinageBreakdownFactory.rows(from: holdings).map { row in
            switch row.standing {
            case .unknownHistory: .unknownHistory(row.severity)
            case .knownLevel: .knownLevel(row.severity)
            }
        }
    }

    /// One installation for the whole suite: ordering only ever compares items within it.
    static let installation = try! CoinageInstallationId(value: Data(repeating: 7, count: 32))

    func keyIndex(_ item: DerivationIndex) -> CoinageKeyIndex {
        CoinageKeyIndex(installation: Self.installation, item: item)
    }

    func hops(_ count: Int) -> [Hop] {
        Array(repeating: .transfer(bundleSize: 1), count: count)
    }

    func coin(
        exponent: Int16 = 5,
        age: Int16,
        fungibility: UInt8?,
        hops: [Hop] = []
    ) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: keyIndex(DerivationIndex(abs(Int(age)) + Int(exponent) * 100)),
            age: age,
            recyclerFungibility: fungibility,
            hops: hops,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: Int(exponent)), count: 32)
        )
    }

    func voucher(exponent: Int16 = 5, fungibility: UInt8) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: keyIndex(900),
            allocatedAt: .distantPast,
            readyAt: .distantPast,
            remoteState: .inRecycler(.init(index: 0, membersCount: 10)),
            recyclerFungibility: fungibility,
            maxRecyclerFungibility: 100,
            publicKey: Data(repeating: 9, count: 32)
        )
    }

    func holding(_ coin: Coin) -> CoinageHoldings.CoinHolding {
        .init(coin: coin, availability: .availableNow)
    }

    func holding(_ voucher: Voucher) -> CoinageHoldings.VoucherHolding {
        .init(voucher: voucher, availability: .availableNow)
    }
}
