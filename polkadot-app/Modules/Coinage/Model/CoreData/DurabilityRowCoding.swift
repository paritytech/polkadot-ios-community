import CoreData
import Coinage
import Foundation
import SubstrateSdk

/// Encodes a durability ``Input`` / ``OwnAsset`` into the typed scalar fields of a
/// `CDDurabilityInput` / `CDDurabilityOutput` row, and back.
///
/// The asset is stored structurally — `assetKind` + `derivationIndex`, or `receivedPubKey` for a
/// coin received from a peer — never as a composite string. This keeps a row self-describing even
/// before its `CDCoin` / `CDVoucher` row exists (outputs are minted after registration), which the
/// opportunistic `coin` / `voucher` relations cannot guarantee.
enum DurabilityRowCoding {
    enum AssetKind: Int16 {
        case coin = 0
        case voucher = 1
    }

    static func encode(_ input: Input, into row: CDDurabilityInput, in context: NSManagedObjectContext) {
        switch input {
        case let .coin(.received(publicKey)):
            row.assetKind = AssetKind.coin.rawValue
            row.receivedPubKey = publicKey.toHex()
        case let .coin(.own(index)):
            row.assetKind = AssetKind.coin.rawValue
            row.derivationIndex = Int64(index)
        case let .recyclerVoucher(index):
            row.assetKind = AssetKind.voucher.rawValue
            row.derivationIndex = Int64(index)
        }
        row.coin = DurabilityAssetLinker.coin(for: input, in: context)
        row.voucher = DurabilityAssetLinker.voucher(for: input, in: context)
    }

    static func encode(_ asset: OwnAsset, into row: CDDurabilityOutput, in context: NSManagedObjectContext) {
        switch asset {
        case let .coin(index):
            row.assetKind = AssetKind.coin.rawValue
            row.derivationIndex = Int64(index)
        case let .recyclerVoucher(index):
            row.assetKind = AssetKind.voucher.rawValue
            row.derivationIndex = Int64(index)
        }
        row.coin = DurabilityAssetLinker.coin(for: asset, in: context)
        row.voucher = DurabilityAssetLinker.voucher(for: asset, in: context)
    }

    static func input(from row: CDDurabilityInput) -> Input? {
        if let hex = row.receivedPubKey, let data = try? Data(hexString: hex) {
            return .coin(.received(data))
        }
        let index = UInt32(truncatingIfNeeded: row.derivationIndex)
        switch AssetKind(rawValue: row.assetKind) {
        case .voucher: return .recyclerVoucher(index)
        case .coin,
             .none: return .coin(.own(index))
        }
    }

    static func ownAsset(from row: CDDurabilityOutput) -> OwnAsset? {
        let index = UInt32(truncatingIfNeeded: row.derivationIndex)
        switch AssetKind(rawValue: row.assetKind) {
        case .voucher: return .recyclerVoucher(index)
        case .coin,
             .none: return .coin(index)
        }
    }
}
