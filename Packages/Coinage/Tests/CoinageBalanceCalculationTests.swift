import BigInt
import Foundation
import Testing
@testable import Coinage

/// Pure bucketing logic for `CoinageBalanceService.calculateBalance` — the iOS port of Android's
/// `RealTotalBalanceUseCaseTest`. No CoreData: tracked assets and their durability overlay are built
/// by hand, so every disposition (spendable / degraded / pending-locked / nowhere) is asserted
/// directly against the calculation.
///
/// Bucket mapping: `secured` → `spendable.fullPrivacy`, `degraded` →
/// `spendable.degraded`, `pending` → `locked`.
@Suite("Coinage balance calculation")
struct CoinageBalanceCalculationTests {
    private let context = DenominationBreakdownContext(
        unit: BigUInt(1_000_000),
        precision: 6,
        maxExponent: 7,
        minExponent: -6
    )

    // Ages relative to the recycling threshold (`recycleAtAge`): below it a coin is spendable, at or
    // above it the coin is awaiting recycling.
    private var spendableAge: Int16 { CoinageConstants.recycleAtAge - 1 }
    private var recyclingAge: Int16 { CoinageConstants.recycleAtAge }

    // MARK: - Coins

    @Test("Empty data returns zero balance")
    func emptyIsZero() {
        expect(coins: [], vouchers: [], fullPrivacy: 0, degraded: 0, locked: 0)
    }

    @Test("Coin younger than recycling age, on chain, is spendable")
    func youngOnChainCoinSpendable() {
        expect(
            coins: [tracked(coin(age: spendableAge, onChain: true, exponent: 1))],
            vouchers: [],
            fullPrivacy: planks(1), degraded: 0, locked: 0
        )
    }

    @Test("Coin gone from the chain is not spendable however young its last age")
    func coinGoneFromChainNotSpendable() {
        expect(
            coins: [tracked(coin(age: spendableAge, onChain: false, exponent: 1))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Coin handed off before its mint finalized is not pending")
    func coinHandedOffBeforeMintNotPending() {
        expect(
            coins: [tracked(coin(age: nil, onChain: false, exponent: 1), state: .init(
                handedOff: true, consumerStatus: nil, minterStatus: .pending
            ))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Coin absent from chain with no minter of ours counts nowhere")
    func coinAbsentNoMinterNowhere() {
        expect(
            coins: [tracked(coin(age: nil, onChain: false, exponent: 1))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Coin absent from chain is pending while the transaction minting it is live")
    func coinAbsentPendingMinterIsPending() {
        expect(
            coins: [tracked(coin(age: nil, onChain: false, exponent: 1), state: minter(.pending))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: planks(1)
        )
    }

    @Test("Coin absent from chain counts nowhere once the transaction minting it failed")
    func coinAbsentFailedMinterNowhere() {
        expect(
            coins: [tracked(coin(age: nil, onChain: false, exponent: 1), state: minter(.failure))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Coin held by a live transaction of ours counts nowhere")
    func coinHeldByLiveConsumerNowhere() {
        expect(
            coins: [tracked(coin(age: 0, onChain: true, exponent: 1), state: consumer(.pending))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Handed off coin counts nowhere")
    func handedOffCoinNowhere() {
        expect(
            coins: [tracked(coin(age: 0, onChain: true, exponent: 1), state: .init(
                handedOff: true, consumerStatus: nil, minterStatus: nil
            ))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Coin at recycling age is pending")
    func coinAtRecyclingAgeIsPending() {
        expect(
            coins: [tracked(coin(age: recyclingAge, onChain: true, exponent: 1))],
            vouchers: [],
            fullPrivacy: 0, degraded: 0, locked: planks(1)
        )
    }

    @Test("Spendable coins go to full privacy, never to degraded")
    func spendableCoinsGoFullPrivacy() {
        expect(
            coins: [
                tracked(coin(age: spendableAge, onChain: true, exponent: 1)),
                tracked(coin(age: 0, onChain: true, exponent: 2, index: 1))
            ],
            vouchers: [],
            fullPrivacy: planks(1) + planks(2), degraded: 0, locked: 0
        )
    }

    // MARK: - Vouchers

    @Test("Voucher secured: past delay, in recycler, full privacy")
    func voucherSecured() {
        expect(
            coins: [],
            vouchers: [tracked(securedVoucher(exponent: 1))],
            fullPrivacy: planks(1), degraded: 0, locked: 0
        )
    }

    @Test("Voucher degraded when in recycler but privacy degraded")
    func voucherDegradedByPrivacy() {
        expect(
            coins: [],
            vouchers: [tracked(voucher(exponent: 1, state: .inRecycler(.init(index: 1)), privacy: .degraded))],
            fullPrivacy: 0, degraded: planks(1), locked: 0
        )
    }

    @Test("Voucher degraded when full privacy but unload delay not passed")
    func voucherDegradedByDelay() {
        expect(
            coins: [],
            vouchers: [tracked(voucher(
                exponent: 1, state: .inRecycler(.init(index: 1)), privacy: .full, readyInFuture: true
            ))],
            fullPrivacy: 0, degraded: planks(1), locked: 0
        )
    }

    @Test("Voucher with unknown location is pending while the transaction minting it is live")
    func voucherUnknownPendingMinter() {
        expect(
            coins: [],
            vouchers: [tracked(voucher(exponent: 1, state: .unlocated), state: minter(.pending))],
            fullPrivacy: 0, degraded: 0, locked: planks(1)
        )
    }

    @Test("Voucher with unknown location counts nowhere once the transaction minting it failed")
    func voucherUnknownFailedMinter() {
        expect(
            coins: [],
            vouchers: [tracked(voucher(exponent: 1, state: .unlocated), state: minter(.failure))],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Onboarding voucher is pending whatever the ledger says about its minter")
    func onboardingVoucherPending() {
        expect(
            coins: [],
            vouchers: [tracked(voucher(exponent: 1, state: .onboarding))],
            fullPrivacy: 0, degraded: 0, locked: planks(1)
        )
    }

    @Test("Voucher held by a live transaction of ours counts nowhere")
    func voucherHeldByLiveConsumerNowhere() {
        expect(
            coins: [],
            vouchers: [tracked(securedVoucher(exponent: 1), state: consumer(.pending))],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Voucher a finalized transaction of ours already spent counts nowhere")
    func voucherSpentByFinalizedNowhere() {
        expect(
            coins: [],
            vouchers: [tracked(securedVoucher(exponent: 1), state: consumer(.finalizedSuccess))],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    @Test("Voucher a failed transaction of ours tried to spend counts again")
    func voucherFailedConsumerCountsAgain() {
        expect(
            coins: [],
            vouchers: [tracked(securedVoucher(exponent: 1), state: consumer(.failure))],
            fullPrivacy: planks(1), degraded: 0, locked: 0
        )
    }

    @Test("Handed off voucher counts nowhere")
    func handedOffVoucherNowhere() {
        expect(
            coins: [],
            vouchers: [tracked(securedVoucher(exponent: 1), state: .init(
                handedOff: true, consumerStatus: nil, minterStatus: nil
            ))],
            fullPrivacy: 0, degraded: 0, locked: 0
        )
    }

    // MARK: - Combined

    @Test("Calculates coins and vouchers correctly across all buckets")
    func combined() {
        let coins = [
            tracked(coin(age: spendableAge, onChain: true, exponent: 1)),
            tracked(coin(age: recyclingAge, onChain: true, exponent: 2, index: 1))
        ]
        let vouchers = [
            tracked(voucher(exponent: 3, state: .inRecycler(.init(index: 1)), privacy: .full, readyInFuture: true)),
            tracked(securedVoucher(exponent: 4)),
            tracked(voucher(exponent: 5, state: .inRecycler(.init(index: 1)), privacy: .degraded))
        ]
        expect(
            coins: coins,
            vouchers: vouchers,
            fullPrivacy: planks(1) + planks(4),
            degraded: planks(3) + planks(5),
            locked: planks(2)
        )
    }
}

// MARK: - Helpers

private extension CoinageBalanceCalculationTests {
    func planks(_ exponent: Int16) -> BigUInt {
        context.valueInPlanks(for: exponent)
    }

    func minter(_ status: CoinageTxStatus) -> CoinageAssetState {
        CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: status)
    }

    func consumer(_ status: CoinageTxStatus) -> CoinageAssetState {
        CoinageAssetState(handedOff: false, consumerStatus: status, minterStatus: nil)
    }

    var untracked: CoinageAssetState {
        CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)
    }

    func coin(age: Int16?, onChain: Bool, exponent: Int16, index: DerivationIndex = 0) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: index,
            age: age,
            isOnchain: onChain,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    func tracked(_ coin: Coin, state: CoinageAssetState? = nil) -> TrackedCoin {
        TrackedCoin(coin: coin, state: state ?? untracked)
    }

    func voucher(
        exponent: Int16,
        state: Voucher.OnChainState,
        privacy: VoucherPrivacyLevel = .degraded,
        readyInFuture: Bool = false,
        index: DerivationIndex = 0
    ) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: Date(timeIntervalSince1970: 0),
            readyAt: readyInFuture ? Date(timeIntervalSinceNow: 3_600) : Date(timeIntervalSinceNow: -3_600),
            remoteState: state,
            privacy: privacy,
            publicKey: Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
        )
    }

    func securedVoucher(exponent: Int16, index: DerivationIndex = 0) -> Voucher {
        voucher(exponent: exponent, state: .inRecycler(.init(index: 1)), privacy: .full, index: index)
    }

    func tracked(_ voucher: Voucher, state: CoinageAssetState? = nil) -> TrackedVoucher {
        TrackedVoucher(voucher: voucher, state: state ?? untracked)
    }

    func expect(
        coins: [TrackedCoin],
        vouchers: [TrackedVoucher],
        fullPrivacy: BigUInt,
        degraded: BigUInt,
        locked: BigUInt,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let result = CoinageBalanceService.calculateBalance(coins: coins, vouchers: vouchers, context: context)
        #expect(result.spendable.fullPrivacy.balanceInPlanks() == fullPrivacy, sourceLocation: sourceLocation)
        #expect(result.spendable.degraded.balanceInPlanks() == degraded, sourceLocation: sourceLocation)
        #expect(result.locked.balanceInPlanks() == locked, sourceLocation: sourceLocation)
    }
}
