import CoreData
import Coinage
import Foundation

/// Resolves the `CDCoin` / `CDVoucher` row a durability ``CoinageTxInput`` or ``OwnAsset`` points at, so
/// input/output rows can hold a real relation to the asset for change propagation.
///
/// Matching is on the asset's derivation index, taken straight from the typed case — a received
/// coin or a not-yet-existing row resolves to `nil`. The row's `identifier` string stays the
/// source of truth; the relation is populated opportunistically.
enum CoinageTxAssetLinker {
    static func coin(for input: CoinageTxInput, in context: NSManagedObjectContext) -> CDCoin? {
        guard case let .coin(.own(index, _)) = input else { return nil }
        return coin(index: index, in: context)
    }

    static func voucher(for input: CoinageTxInput, in context: NSManagedObjectContext) -> CDVoucher? {
        guard case let .recyclerVoucher(index, _) = input else { return nil }
        return voucher(index: index, in: context)
    }

    static func coin(for asset: OwnAsset, in context: NSManagedObjectContext) -> CDCoin? {
        guard case let .coin(index, _) = asset else { return nil }
        return coin(index: index, in: context)
    }

    static func voucher(for asset: OwnAsset, in context: NSManagedObjectContext) -> CDVoucher? {
        guard case let .recyclerVoucher(index, _) = asset else { return nil }
        return voucher(index: index, in: context)
    }
}

private extension CoinageTxAssetLinker {
    static func coin(index: DerivationIndex, in context: NSManagedObjectContext) -> CDCoin? {
        fetchFirst("CDCoin", identifier: Coin.identifier(for: index), in: context)
    }

    static func voucher(index: DerivationIndex, in context: NSManagedObjectContext) -> CDVoucher? {
        fetchFirst("CDVoucher", identifier: Voucher.identifier(for: index), in: context)
    }

    static func fetchFirst<T: NSManagedObject>(
        _ entity: String,
        identifier: String,
        in context: NSManagedObjectContext
    ) -> T? {
        let request = NSFetchRequest<T>(entityName: entity)
        request.predicate = NSPredicate(format: "identifier == %@", identifier)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
