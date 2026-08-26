import Foundation
import CoreData
import Coinage
import Operation_iOS
import SubstrateSdk

/// Maps ``DurabilityEntry`` to `CDDurability`.
///
/// Inputs and outputs are immutable: they are written once when the entry is first inserted and
/// never rewritten, so a status update only touches the entry's own fields. Each row references
/// its asset through the `CDCoin` / `CDVoucher` relation — or `receivedPubKey` for a coin received
/// from a peer — which must already exist at registration.
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

        guard let checkpointHash = entity.checkpointHash, let checkpointNumber = entity.checkpointNumber else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurability.checkpointHash))
        }

        let checkpoint = try BlockRef(
            number: checkpointNumber.uint32Value,
            hash: Data(hexString: checkpointHash)
        )

        let txHash: Data? =
            if let txHashString = entity.txHash {
                try Data(hexString: txHashString)
            } else {
                nil
            }

        let successDetectedAt: BlockRef? =
            if let successHash = entity.successHash, let successNumber = entity.successNumber {
                try BlockRef(number: successNumber.uint32Value, hash: Data(hexString: successHash))
            } else {
                nil
            }

        guard let createdAt = entity.createdAt else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurability.createdAt))
        }

        return try DurabilityEntry(
            id: id,
            sequence: entity.sequence,
            inputs: transformInputs(from: entity.inputs),
            outputs: transformOutputs(from: entity.outputs),
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: UInt32(bitPattern: entity.mortality),
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }

    func populate(
        entity: CDDurability,
        from model: DurabilityEntry,
        using context: NSManagedObjectContext
    ) throws {
        let isNew = entity.identifier == nil

        entity.identifier = model.identifier
        entity.sequence = model.sequence
        entity.status = Int16(model.status.rawValue)
        entity.createdAt = model.createdAt
        entity.mortality = Int32(bitPattern: model.mortality)
        entity.checkpointHash = model.checkpoint.hash.toHex()
        entity.checkpointNumber = NSNumber(value: model.checkpoint.number)
        entity.txHash = model.txHash?.toHex()
        entity.successHash = model.successDetectedAt?.hash.toHex()
        entity.successNumber = model.successDetectedAt.map { NSNumber(value: $0.number) }

        // Inputs and outputs never change once the entry exists — write them only on first insert.
        if isNew {
            try populateInputs(entity: entity, inputs: model.inputs, using: context)
            try populateOutputs(entity: entity, outputs: model.outputs, using: context)
        }

        touchRelatedAssets(of: entity, in: context)
    }
}

// MARK: - Transform

private extension DurabilityEntryMapper {
    func transformInputs(from rows: NSSet?) throws -> [DurabilityInput] {
        guard let rows = rows as? Set<CDDurabilityInput> else { return [] }
        return try rows.compactMap { row in
            if let hex = row.receivedPubKey {
                let publicKey = try Data(hexString: hex)

                return .coin(.received(publicKey))
            }
            if let coin = row.coin {
                return .coin(.own(DerivationIndex.fromCoreData(coin.derivationIndex)))
            }
            if let voucher = row.voucher {
                return .recyclerVoucher(DerivationIndex.fromCoreData(voucher.derivationIndex))
            }
            return nil
        }
    }

    func transformOutputs(from rows: NSSet?) -> [OwnAsset] {
        guard let rows = rows as? Set<CDDurabilityOutput> else { return [] }
        return rows.compactMap { row in
            if let coin = row.coin {
                return .coin(DerivationIndex.fromCoreData(coin.derivationIndex))
            }
            if let voucher = row.voucher {
                return .recyclerVoucher(DerivationIndex.fromCoreData(voucher.derivationIndex))
            }
            return nil
        }
    }
}

// MARK: - Populate

private extension DurabilityEntryMapper {
    func populateInputs(
        entity: CDDurability,
        inputs: [DurabilityInput],
        using context: NSManagedObjectContext
    ) throws {
        for input in inputs {
            guard let row = insert("CDDurabilityInput", context) as CDDurabilityInput? else {
                throw CoreDataMapperError.unsupported
            }

            row.identifier = UUID().uuidString
            row.entry = entity

            switch input {
            case let .coin(coinInput):
                switch coinInput {
                case .own:
                    if let coin = DurabilityAssetLinker.coin(for: input, in: context) {
                        row.coin = coin
                    } else {
                        throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityInput.coin))
                    }
                case let .received(accountId):
                    row.receivedPubKey = accountId.toHex()
                }
            case .recyclerVoucher:
                if let voucher = DurabilityAssetLinker.voucher(for: input, in: context) {
                    row.voucher = voucher
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityInput.voucher))
                }
            }
        }
    }

    func populateOutputs(
        entity: CDDurability,
        outputs: [OwnAsset],
        using context: NSManagedObjectContext
    ) throws {
        for output in outputs {
            guard let row = insert("CDDurabilityOutput", context) as CDDurabilityOutput? else {
                throw CoreDataMapperError.unsupported
            }

            row.identifier = UUID().uuidString
            row.entry = entity

            switch output {
            case .coin:
                if let coin = DurabilityAssetLinker.coin(for: output, in: context) {
                    row.coin = coin
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityOutput.coin))
                }
            case .recyclerVoucher:
                if let voucher = DurabilityAssetLinker.voucher(for: output, in: context) {
                    row.voucher = voucher
                } else {
                    throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDDurabilityOutput.voucher))
                }
            }
        }
    }

    /// Signals the linked coins/vouchers as changed so their CoreData snapshot subscribers re-emit
    /// when this entry's status changes — the `willChange`/`didChange` TouchParent pattern.
    func touchRelatedAssets(of entity: CDDurability, in _: NSManagedObjectContext) {
        for row in (entity.inputs as? Set<CDDurabilityInput>) ?? [] {
            if let coin = row.coin {
                let key = #keyPath(CDCoin.durabilityInputs)
                coin.willChangeValue(forKey: key)
                coin.didChangeValue(forKey: key)
            }

            if let voucher = row.voucher {
                let key = #keyPath(CDVoucher.durabilityInputs)
                voucher.willChangeValue(forKey: key)
                voucher.didChangeValue(forKey: key)
            }
        }

        for row in (entity.outputs as? Set<CDDurabilityOutput>) ?? [] {
            if let coin = row.coin {
                let key = #keyPath(CDCoin.durabilityOutput)
                coin.willChangeValue(forKey: key)
                coin.didChangeValue(forKey: key)
            }

            if let voucher = row.voucher {
                let key = #keyPath(CDVoucher.durabilityOutput)
                voucher.willChangeValue(forKey: key)
                voucher.didChangeValue(forKey: key)
            }
        }
    }

    func insert<Entity: NSManagedObject>(_ entityName: String, _ context: NSManagedObjectContext) -> Entity? {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as? Entity
    }
}
