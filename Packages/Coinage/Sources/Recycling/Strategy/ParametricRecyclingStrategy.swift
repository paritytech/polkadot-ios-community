import Foundation
import SubstrateSdk
import BigInt

/// The single recycling policy. Both decorators wrap an instance of this.
public struct ParametricRecyclingStrategy: CoinRecyclingStrategyProtocol {
    private let params: RecyclingParams

    public init(params: RecyclingParams) {
        self.params = params
    }

    public func evaluate(
        coins: [Coin],
        snapshot: RecyclingSnapshot,
        context: DenominationBreakdownContext
    ) -> RecyclingVerdicts {
        let budget = params.maxUnavailableBalance.mul(value: snapshot.total)
        var unavailable = snapshot.unavailable
        var verdicts = RecyclingVerdicts()

        // Oldest-first: a coin nearer the forced-recycle age has the most to lose by waiting, so it
        // spends the budget first.
        for coin in coins.sorted(by: { Self.age(of: $0) > Self.age(of: $1) }) {
            // Headroom, not fit: while anything is left in the budget the next coin is admitted even
            // if it overshoots, so a coin larger than the whole budget still recycles instead of
            // waiting for the forced age. A zero budget admits nothing (`unavailable < 0` is never true).
            let gated = Self.age(of: coin) >= params.minRecyclingAge && unavailable < budget
            if gated {
                unavailable += context.valueInPlanks(for: coin.exponent)
            }
            verdicts[coin.derivationIndex] = gated ? .toRecycle : .allowUse
        }

        return verdicts
    }

    public func isVoucherUsable(_ voucher: Voucher, context: VoucherUsabilityContext) -> Bool {
        guard voucher.isInRecycler else { return false }

        let members = BigUInt(voucher.recyclerMembers ?? 0)
        let capacity = BigUInt(context.capacity(for: voucher.exponent))

        // members >= ceil(capacity * requiredRingFill) ⟺ members * den >= capacity * num, integer-exact.
        let ringFilled = members * params.requiredRingFill.denominator
            >= capacity * params.requiredRingFill.numerator

        // Below a full ring the random unload delay is an acceptable substitute for anonymity-set
        // size; at 100% nothing but a full ring will do.
        let delayElapsed = params.requiredRingFill.isLess(than: .full) && voucher.readyAt < context.now

        return ringFilled || delayElapsed
    }

    public func allowsConfirmedSpend() -> Bool {
        params.allowsConfirmedSpend
    }
}

private extension ParametricRecyclingStrategy {
    /// Unknown age maps to -1, so an unknown-age coin fails every `age >= minRecyclingAge` test as
    /// long as presets stay at or above `minRecyclableAge` (1). A second guard lives in
    /// `preClassifyCoins`, which never passes an unknown-age coin here.
    static func age(of coin: Coin) -> Int16 {
        coin.age ?? -1
    }
}
