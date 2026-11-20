import Foundation
import Testing
@testable import Coinage

struct VoucherReadinessTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test(
        "Balanced releases a voucher once its anonymity delay has elapsed",
        arguments: [
            (members: 10, unloaded: 2, elapsed: 600, expected: true),
            (members: 10, unloaded: 2, elapsed: 540, expected: false),
            (members: 20, unloaded: 4, elapsed: 300, expected: true),
            (members: 20, unloaded: 4, elapsed: 299, expected: false),
            (members: 6, unloaded: 2, elapsed: 1_200, expected: true),
            (members: 6, unloaded: 2, elapsed: 1_140, expected: false)
        ]
    )
    func balancedReleasesAfterAnonymityDelay(
        _ testCase: (members: UInt32, unloaded: UInt32, elapsed: TimeInterval, expected: Bool)
    ) {
        let candidate = voucher(
            members: testCase.members,
            enteredAt: now.addingTimeInterval(-testCase.elapsed),
            unloaded: testCase.unloaded
        )
        #expect(strategy(.balanced).isVoucherUsable(candidate, context: context()) == testCase.expected)
    }

    @Test("A voucher not yet confirmed in the ring is never ready by time")
    func unconfirmedInclusionIsNeverReady() {
        let candidate = voucher(members: 10, enteredAt: nil, unloaded: 0)
        #expect(!strategy(.balanced).isVoucherUsable(candidate, context: context()))
    }

    @Test(
        "A ring with no unclaimed members is never ready by time",
        arguments: [(members: 5, unloaded: 5), (members: 5, unloaded: 9)]
    )
    func exhaustedRingIsNeverReadyByTime(_ testCase: (members: UInt32, unloaded: UInt32)) {
        let candidate = voucher(
            members: testCase.members,
            enteredAt: now.addingTimeInterval(-86_400),
            unloaded: testCase.unloaded
        )
        #expect(!strategy(.balanced).isVoucherUsable(candidate, context: context()))
    }

    @Test(
        "A voucher with an unknown unloaded count is ready only at the ring fill target",
        arguments: [(members: 10, expected: false), (members: 154, expected: true)]
    )
    func unknownUnloadedCountWaitsForRingFill(_ testCase: (members: UInt32, expected: Bool)) {
        let candidate = voucher(
            members: testCase.members,
            enteredAt: now.addingTimeInterval(-86_400),
            unloaded: nil
        )
        #expect(strategy(.balanced).isVoucherUsable(candidate, context: context()) == testCase.expected)
    }

    @Test(
        "Max privacy releases a voucher after its own anonymity delay",
        arguments: [(elapsed: 600, expected: true), (elapsed: 540, expected: false)]
    )
    func maxPrivacyUsesItsOwnAnonymityDelay(_ testCase: (elapsed: TimeInterval, expected: Bool)) {
        let candidate = voucher(
            members: 20,
            enteredAt: now.addingTimeInterval(-testCase.elapsed),
            unloaded: 4
        )
        #expect(strategy(.maxPrivacy).isVoucherUsable(candidate, context: context()) == testCase.expected)
    }

    @Test("Min privacy releases a voucher immediately")
    func minPrivacyIsImmediate() {
        let candidate = voucher(members: 1, enteredAt: nil)
        #expect(strategy(.minPrivacy).isVoucherUsable(candidate, context: context()))
    }

    @Test("Balanced uses the privacy config it is built from")
    func balancedHonoursInjectedConfig() {
        let config = CoinagePrivacyConfig(
            balanced: .init(ringFillPercent: 50, anonymityMinutes: 1, anonymityMembers: 1),
            maxPrivacy: CoinagePrivacyConfig.bundled.maxPrivacy
        )
        let strategy = strategy(.balanced, config: config)
        let justBefore = voucher(members: 2, enteredAt: now.addingTimeInterval(-59), unloaded: 1)
        let justAfter = voucher(members: 2, enteredAt: now.addingTimeInterval(-60), unloaded: 1)

        #expect(!strategy.isVoucherUsable(justBefore, context: context()))
        #expect(strategy.isVoucherUsable(justAfter, context: context()))
    }

    @Test(
        "Ready time is the entry time plus the anonymity delay",
        arguments: [
            (
                members: 10,
                unloaded: 2,
                enteredAt: Date(timeIntervalSince1970: 1_000),
                expected: Date(timeIntervalSince1970: 1_600)
            ),
            (members: 2, unloaded: 2, enteredAt: Date(timeIntervalSince1970: 1_000), expected: nil),
            (members: 10, unloaded: nil, enteredAt: Date(timeIntervalSince1970: 1_000), expected: nil),
            (members: 10, unloaded: 2, enteredAt: nil, expected: nil)
        ] as [(members: UInt32, unloaded: UInt32?, enteredAt: Date?, expected: Date?)]
    )
    func readyAtDerivesFromEntryAndUnclaimedMembers(
        _ testCase: (members: UInt32, unloaded: UInt32?, enteredAt: Date?, expected: Date?)
    ) {
        let readiness = RecyclingStrategyType.balanced.params(
            forcedRecyclingAge: CoinageConstants.recycleAtAge,
            privacyConfig: .bundled
        ).voucherReadiness
        let candidate = voucher(members: testCase.members, enteredAt: testCase.enteredAt, unloaded: testCase.unloaded)
        #expect(readiness.readyAt(for: candidate) == testCase.expected)
    }

    @Test
    func ringFillUsesNinetyAndTwentyPercentWithoutRoundingDown() {
        let capacity = 767
        let ninetyPercentMembers = UInt32((Double(capacity) * 0.9).rounded(.up))
        let twentyPercentMembers = UInt32((Double(capacity) * 0.2).rounded(.up))

        for (type, minimumMembers) in [
            (RecyclingStrategyType.maxPrivacy, ninetyPercentMembers),
            (.balanced, twentyPercentMembers)
        ] {
            let strategy = strategy(type)
            let testCases = [
                (members: minimumMembers - 1, expected: false),
                (members: minimumMembers, expected: true)
            ]

            for testCase in testCases {
                let candidate = voucher(members: testCase.members, enteredAt: nil)
                #expect(
                    strategy.isVoucherUsable(candidate, context: context(capacity: capacity))
                        == testCase.expected
                )
            }
        }
    }

    @Test
    func ringFillCanReleaseBeforeEitherWaitingRequirement() {
        let capacity = 10
        let ninetyPercentMembers = UInt32((Double(capacity) * 0.9).rounded(.up))

        #expect(strategy(.maxPrivacy).isVoucherUsable(
            voucher(members: ninetyPercentMembers, enteredAt: nil),
            context: context(capacity: capacity)
        ))
    }
}

private extension VoucherReadinessTests {
    func strategy(
        _ type: RecyclingStrategyType,
        config: CoinagePrivacyConfig = .bundled
    ) -> ParametricRecyclingStrategy {
        ParametricRecyclingStrategy(
            params: type.params(forcedRecyclingAge: CoinageConstants.recycleAtAge, privacyConfig: config)
        )
    }

    func context(capacity: Int = 767) -> VoucherUsabilityContext {
        VoucherUsabilityContext(ringCapacities: [1: capacity], now: now)
    }

    func voucher(members: UInt32, enteredAt: Date?, unloaded: UInt32? = nil) -> Voucher {
        Voucher(
            exponent: 1,
            derivationIndex: 0,
            allocatedAt: .distantPast,
            readyAt: .distantPast,
            remoteState: .inRecycler(.init(
                index: 1,
                membersCount: members,
                enteredAt: enteredAt,
                unloadedCount: unloaded
            )),
            publicKey: Data(repeating: 0, count: 32)
        )
    }
}
