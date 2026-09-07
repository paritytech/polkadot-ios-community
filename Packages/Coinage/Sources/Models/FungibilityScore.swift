import Foundation

/// A holding's effective fungibility on the `0...100` scale.
///
/// Kept in the domain layer rather than derived per-view so the rule has one definition:
/// a voucher scores its recycler's fungibility outright, while a coin is discounted for
/// every hop in its provenance.
public protocol FungibilityScoring {
    /// `nil` when the inputs are not known well enough to score the holding.
    var fungibilityScore: UInt8? { get }
}

extension Voucher: FungibilityScoring {
    public var fungibilityScore: UInt8? {
        recyclerFungibility
    }
}

extension Coin: FungibilityScoring {
    public var fungibilityScore: UInt8? {
        guard let recyclerFungibility else { return nil }

        let penalty = Int(CoinageConstants.hopFungibilityPenalty) * hops.count
        return UInt8(max(0, Int(recyclerFungibility) - penalty))
    }
}
