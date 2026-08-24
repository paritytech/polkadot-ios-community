import Foundation
import CoreData
import Coinage
import Operation_iOS
import SubstrateSdk

/// Maps ``DurabilityEntry`` to `CDDurabilityEntry`.
///
/// Inputs and outputs are stored in a separate `CDEntryAsset` relation, keyed by stable
/// identifiers that the engine uses for set operations.
final class DurabilityEntryMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = DurabilityEntry
    typealias CoreDataEntity = CDDurabilityEntry

    var entityIdentifierFieldName: String { #keyPath(CDDurabilityEntry.identifier) }

    private static let roleInput: Int16 = 0
    private static let roleOutput: Int16 = 1

    func transform(entity: CDDurabilityEntry) throws -> DurabilityEntry {
        guard let identifier = entity.identifier, let id = UUID(uuidString: identifier) else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CDDurabilityEntry.identifier)
            )
        }
        guard let checkpointHash = entity.checkpointHash else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CDDurabilityEntry.checkpointHash)
            )
        }
        guard let status = EntryStatus(rawValue: Int(entity.status)) else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CDDurabilityEntry.status)
            )
        }

        let successDetectedAt = entity.successBlockHash.map {
            BlockRef(number: UInt32(bitPattern: entity.successBlockNumber), hash: $0)
        }

        let inputs = transformInputs(from: entity.assets)
        let outputs = transformOutputs(from: entity.assets)

        return DurabilityEntry(
            id: id,
            sequence: entity.sequence,
            inputs: inputs,
            outputs: outputs,
            txHash: entity.txHash,
            checkpoint: BlockRef(
                number: UInt32(bitPattern: entity.checkpointNumber),
                hash: checkpointHash
            ),
            mortality: UInt32(bitPattern: entity.mortality),
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: entity.createdAt ?? Date()
        )
    }

    func populate(
        entity: CDDurabilityEntry,
        from model: DurabilityEntry,
        using context: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.sequence = model.sequence
        entity.txHash = model.txHash
        entity.checkpointNumber = Int32(bitPattern: model.checkpoint.number)
        entity.checkpointHash = model.checkpoint.hash
        entity.mortality = Int32(bitPattern: model.mortality)
        entity.successBlockNumber = Int32(bitPattern: model.successDetectedAt?.number ?? 0)
        entity.successBlockHash = model.successDetectedAt?.hash
        entity.status = Int16(model.status.rawValue)
        entity.createdAt = model.createdAt

        try populateAssets(entity: entity, inputs: model.inputs, outputs: model.outputs, using: context)
    }
}

// MARK: - AssetCoding

enum AssetCoding {
    static func input(from identifier: String) -> Input? {
        let parts = identifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let value = String(parts[1])

        switch parts[0] {
        case "coin":
            return UInt32(value).map { .coin(.own($0)) }
        case "received":
            return (try? Data(hexString: value)).map { .coin(.received($0)) }
        case "voucher":
            return UInt32(value).map { .recyclerVoucher($0) }
        default:
            return nil
        }
    }

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

// MARK: - Private

private extension DurabilityEntryMapper {
    func transformInputs(from assets: NSSet?) -> [Input] {
        guard let assets = assets as? Set<CDEntryAsset> else { return [] }
        return assets
            .filter { $0.role == Self.roleInput }
            .sorted { $0.index < $1.index }
            .compactMap { asset in
                guard let identifier = asset.identifier else { return nil }
                return AssetCoding.input(from: identifier)
            }
    }

    func transformOutputs(from assets: NSSet?) -> [OwnAsset] {
        guard let assets = assets as? Set<CDEntryAsset> else { return [] }
        return assets
            .filter { $0.role == Self.roleOutput }
            .sorted { $0.index < $1.index }
            .compactMap { asset in
                guard let identifier = asset.identifier else { return nil }
                return AssetCoding.ownAsset(from: identifier)
            }
    }

    func populateAssets(
        entity: CDDurabilityEntry,
        inputs: [Input],
        outputs: [OwnAsset],
        using context: NSManagedObjectContext
    ) throws {
        (entity.assets as? Set<CDEntryAsset>)?.forEach { context.delete($0) }

        try insertAssets(
            identifiers: inputs.map(\.identifier),
            role: Self.roleInput,
            into: entity,
            context: context
        )
        try insertAssets(
            identifiers: outputs.map(\.identifier),
            role: Self.roleOutput,
            into: entity,
            context: context
        )
    }

    func insertAssets(
        identifiers: [String],
        role: Int16,
        into entity: CDDurabilityEntry,
        context: NSManagedObjectContext
    ) throws {
        for (index, identifier) in identifiers.enumerated() {
            guard let asset = NSEntityDescription.insertNewObject(
                forEntityName: "CDEntryAsset",
                into: context
            ) as? CDEntryAsset else {
                throw CoreDataMapperError.missingRequiredData(
                    keyPath: #keyPath(CDEntryAsset.identifier)
                )
            }
            asset.identifier = identifier
            asset.role = role
            asset.index = Int16(index)
            asset.entry = entity
        }
    }
}
