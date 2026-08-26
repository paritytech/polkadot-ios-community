import Foundation
import CoreData
import Coinage
import Operation_iOS
import SubstrateSdk

/// Maps ``DurabilityEntry`` to `CDDurability`.
///
/// Inputs and outputs are immutable: they are written once when the entry is first inserted and
/// never rewritten, so a status update only touches the entry's own fields. Each row identifies
/// its asset through typed scalars (see ``DurabilityRowCoding``); the `CDCoin` / `CDVoucher`
/// relation is populated opportunistically — and lazily on later saves, once an output's coin
/// row exists — so a status change can be propagated to the asset's subscribers.
final class DurabilityEntryMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = DurabilityEntry
    typealias CoreDataEntity = CDDurability

    var entityIdentifierFieldName: String { #keyPath(CDDurability.identifier) }

    func transform(entity: CDDurability) throws -> DurabilityEntry {
        guard let identifier = entity.identifier, let id = UUID(uuidString: identifier) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurability.identifier))
        }
        guard let status = EntryStatus(rawValue: Int(entity.status)) else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurability.status))
        }

        let checkpoint = try blockRef(
            hash: entity.checkpointHash,
            number: entity.checkpointNumber,
            keyPath: #keyPath(CDDurability.checkpointHash)
        )

        return DurabilityEntry(
            id: id,
            sequence: entity.sequence,
            inputs: transformInputs(from: entity.inputs),
            outputs: transformOutputs(from: entity.outputs),
            txHash: entity.txHash.flatMap { try? Data(hexString: $0) },
            checkpoint: checkpoint,
            mortality: UInt32(truncatingIfNeeded: entity.mortality),
            successDetectedAt: try? blockRef(
                hash: entity.successHash,
                number: entity.successNumber,
                keyPath: #keyPath(CDDurability.successHash)
            ),
            status: status,
            createdAt: entity.createdAt ?? Date()
        )
    }

    func populate(
        entity: CDDurability,
        from model: DurabilityEntry,
        using context: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.sequence = model.sequence
        entity.status = Int16(model.status.rawValue)
        entity.createdAt = model.createdAt
        entity.mortality = Int64(model.mortality)
        entity.checkpointHash = model.checkpoint.hash.toHex()
        entity.checkpointNumber = NSNumber(value: model.checkpoint.number)
        entity.txHash = model.txHash?.toHex()
        entity.successHash = model.successDetectedAt?.hash.toHex()
        entity.successNumber = model.successDetectedAt.map { NSNumber(value: $0.number) }

        // Inputs and outputs never change once the entry exists — write them only on first insert.
        if entity.isInserted {
            try populateInputs(entity: entity, inputs: model.inputs, using: context)
            try populateOutputs(entity: entity, outputs: model.outputs, using: context)
        }

        touchRelatedAssets(of: entity, in: context)
    }
}

// MARK: - AssetCoding

/// Parses the domain identifier of a handoff mark ("coin:N" / "voucher:N") back into an asset.
enum AssetCoding {
    static func ownAsset(from identifier: String) -> OwnAsset? {
        let parts = identifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let index = UInt32(parts[1]) else { return nil }

        switch parts[0] {
        case "coin": return .coin(index)
        case "voucher": return .recyclerVoucher(index)
        default: return nil
        }
    }
}

// MARK: - Transform

private extension DurabilityEntryMapper {
    func blockRef(hash: String?, number: NSNumber?, keyPath: String) throws -> BlockRef {
        guard let hash, let number else {
            throw CoreDataMapperError.missingRequiredData(keyPath: keyPath)
        }
        return try BlockRef(number: number.uint32Value, hash: Data(hexString: hash))
    }

    func transformInputs(from rows: NSSet?) -> [Input] {
        guard let rows = rows as? Set<CDDurabilityInput> else { return [] }
        return rows.sorted { $0.index < $1.index }.compactMap(DurabilityRowCoding.input(from:))
    }

    func transformOutputs(from rows: NSSet?) -> [OwnAsset] {
        guard let rows = rows as? Set<CDDurabilityOutput> else { return [] }
        return rows.sorted { $0.index < $1.index }.compactMap(DurabilityRowCoding.ownAsset(from:))
    }
}

// MARK: - Populate

private extension DurabilityEntryMapper {
    func populateInputs(
        entity: CDDurability,
        inputs: [Input],
        using context: NSManagedObjectContext
    ) throws {
        for (index, input) in inputs.enumerated() {
            guard let row = insert("CDDurabilityInput", context) as CDDurabilityInput? else {
                throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityInput.identifier))
            }
            row.identifier = UUID().uuidString
            row.index = Int16(index)
            row.entry = entity
            DurabilityRowCoding.encode(input, into: row, in: context)
        }
    }

    func populateOutputs(
        entity: CDDurability,
        outputs: [OwnAsset],
        using context: NSManagedObjectContext
    ) throws {
        for (index, output) in outputs.enumerated() {
            guard let row = insert("CDDurabilityOutput", context) as CDDurabilityOutput? else {
                throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityOutput.identifier))
            }
            row.identifier = UUID().uuidString
            row.index = Int16(index)
            row.entry = entity
            DurabilityRowCoding.encode(output, into: row, in: context)
        }
    }

    /// Signals the linked coins/vouchers as changed so their CoreData snapshot subscribers re-emit
    /// when this entry's status changes — the `willChange`/`didChange` TouchParent pattern. Relations
    /// are lazily filled here for outputs whose coin row did not yet exist at registration.
    func touchRelatedAssets(of entity: CDDurability, in context: NSManagedObjectContext) {
        var coins: Set<CDCoin> = []
        var vouchers: Set<CDVoucher> = []

        for row in (entity.inputs as? Set<CDDurabilityInput>) ?? [] {
            guard let input = DurabilityRowCoding.input(from: row) else { continue }
            if let coin = row.coin ?? DurabilityAssetLinker.coin(for: input, in: context) {
                row.coin = coin
                coins.insert(coin)
            }
            if let voucher = row.voucher ?? DurabilityAssetLinker.voucher(for: input, in: context) {
                row.voucher = voucher
                vouchers.insert(voucher)
            }
        }

        for row in (entity.outputs as? Set<CDDurabilityOutput>) ?? [] {
            guard let output = DurabilityRowCoding.ownAsset(from: row) else { continue }
            if let coin = row.coin ?? DurabilityAssetLinker.coin(for: output, in: context) {
                row.coin = coin
                coins.insert(coin)
            }
            if let voucher = row.voucher ?? DurabilityAssetLinker.voucher(for: output, in: context) {
                row.voucher = voucher
                vouchers.insert(voucher)
            }
        }

        for coin in coins {
            let key = #keyPath(CDCoin.durabilityInputs)
            coin.willChangeValue(forKey: key)
            coin.didChangeValue(forKey: key)
        }
        for voucher in vouchers {
            let key = #keyPath(CDVoucher.durabilityInputs)
            voucher.willChangeValue(forKey: key)
            voucher.didChangeValue(forKey: key)
        }
    }

    func insert<Entity: NSManagedObject>(_ entityName: String, _ context: NSManagedObjectContext) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }
}
