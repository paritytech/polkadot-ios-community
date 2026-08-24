import Foundation

/// What an asset is currently doing, derived from the live entry set and handoff marks.
///
/// Never stored as truth: `DurabilityService` computes it on demand from entries.
public enum AssetStatus: Sendable, Equatable {
    /// Not claimed by any live entry and carrying no handoff mark.
    case idle
    /// An input of a live entry. Matches the spec's `reserved(a)`: outputs of a live entry are
    /// NOT reserved — their disposition lives in `Coin.State`.
    case reserved
    /// Handed to a peer. Terminal for local purposes — the asset can never re-enter an
    /// entry.
    case handedOff
}

/// The two facts about an asset that only the durability subsystem knows.
public struct CoinageAssetState: Equatable, Sendable {
    /// The lock and disposition of the asset.
    public let lock: AssetStatus
    /// The status of the minting entry, or nil if no local entry minted this asset.
    /// Used to distinguish absence before minting from absence after revert.
    public let minterStatus: EntryStatus?

    public init(lock: AssetStatus, minterStatus: EntryStatus?) {
        self.lock = lock
        self.minterStatus = minterStatus
    }
}
