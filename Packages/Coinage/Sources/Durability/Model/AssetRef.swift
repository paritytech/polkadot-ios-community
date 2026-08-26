import Foundation
import SubstrateSdk

/// A coin or voucher consumed by a durability entry.
public enum DurabilityInput: Hashable, Sendable {
    case coin(CoinInput)
    case recyclerVoucher(DerivationIndex)
}

/// A coin an entry consumes: either one this wallet minted, addressed by derivation index,
/// or one received from a peer, addressed by the on-chain public key it was sent to.
public enum CoinInput: Hashable, Sendable {
    case own(DerivationIndex)
    case received(Data)
}

/// An asset this wallet mints, and can therefore hold local projected state for.
public enum OwnAsset: Hashable, Sendable {
    case coin(DerivationIndex)
    case recyclerVoucher(DerivationIndex)
}

/// An asset a durability entry mints. An output is always one this wallet owns.
public typealias DurabilityOutput = OwnAsset

public extension OwnAsset {
    /// Stable key for storage rows and set operations. Shared with ``DurabilityInput/identifier`` so
    /// an output and an input naming the same asset compare equal.
    var identifier: String {
        switch self {
        case let .coin(index): "coin:\(index)"
        case let .recyclerVoucher(index): "voucher:\(index)"
        }
    }

    var isCoin: Bool {
        if case .coin = self { return true }
        return false
    }

    /// Derivation index, which every own asset has.
    var derivationIndex: DerivationIndex {
        switch self {
        case let .coin(index),
             let .recyclerVoucher(index): index
        }
    }

    var asInput: DurabilityInput {
        switch self {
        case let .coin(index): .coin(.own(index))
        case let .recyclerVoucher(index): .recyclerVoucher(index)
        }
    }
}

public extension DurabilityInput {
    var identifier: String {
        switch self {
        case let .coin(.own(index)): "coin:\(index)"
        case let .coin(.received(publicKey)): "received:\(publicKey.toHex())"
        case let .recyclerVoucher(index): "voucher:\(index)"
        }
    }

    var isCoin: Bool {
        if case .coin = self { return true }
        return false
    }

    /// True when this wallet minted the asset, so its provenance can be traced to an
    /// entry.
    var isOwn: Bool {
        ownAsset != nil
    }

    /// The own-asset view of this input, or `nil` for a coin received from a peer.
    var ownAsset: OwnAsset? {
        switch self {
        case let .coin(.own(index)): .coin(index)
        case let .recyclerVoucher(index): .recyclerVoucher(index)
        case .coin(.received): nil
        }
    }
}
