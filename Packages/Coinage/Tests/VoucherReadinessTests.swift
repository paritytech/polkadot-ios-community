import Foundation
import Testing
@testable import Coinage

struct VoucherReadinessTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test(arguments: [RecyclingStrategyType.balanced, .maxPrivacy])
    func waitingRequiresBothMembersAndConfirmedAge(_ type: RecyclingStrategyType) {
        let strategy = strategy(type)
        let vouchers = [
            voucher(members: 31, enteredAt: now.addingTimeInterval(-600)),
            voucher(members: 32, enteredAt: now.addingTimeInterval(-599.999)),
            voucher(members: 32, enteredAt: now.addingTimeInterval(-600)),
            voucher(members: 32, enteredAt: nil)
        ]

        #expect(vouchers.map { strategy.isVoucherUsable($0, context: context()) } == [false, false, true, false])
    }

    @Test
    func ringFillUsesNinetyAndTwentyPercentWithoutRoundingDown() {
        for (type, threshold) in [(RecyclingStrategyType.maxPrivacy, 691), (.balanced, 154)] {
            let vouchers = [threshold - 1, threshold].map { voucher(members: UInt32($0), enteredAt: nil) }
            #expect(vouchers.map { strategy(type).isVoucherUsable($0, context: context()) } == [false, true])
        }
    }

    @Test
    func ringFillCanReleaseBeforeEitherWaitingRequirement() {
        #expect(strategy(.maxPrivacy).isVoucherUsable(
            voucher(members: 9, enteredAt: nil),
            context: context(capacity: 10)
        ))
    }
}

private extension VoucherReadinessTests {
    func strategy(_ type: RecyclingStrategyType) -> ParametricRecyclingStrategy {
        ParametricRecyclingStrategy(params: type.params(forcedRecyclingAge: CoinageConstants.recycleAtAge))
    }

    func context(capacity: Int = 767) -> VoucherUsabilityContext {
        VoucherUsabilityContext(ringCapacities: [1: capacity], now: now)
    }

    func voucher(members: UInt32, enteredAt: Date?) -> Voucher {
        Voucher(
            exponent: 1,
            derivationIndex: 0,
            allocatedAt: .distantPast,
            readyAt: .distantPast,
            remoteState: .inRecycler(.init(index: 1, membersCount: members, enteredAt: enteredAt)),
            publicKey: Data(repeating: 0, count: 32)
        )
    }
}
