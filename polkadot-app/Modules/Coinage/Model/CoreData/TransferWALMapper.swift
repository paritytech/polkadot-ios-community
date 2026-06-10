import Coinage
import CoreData
import Foundation
import Operation_iOS

final class TransferWALMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = TransferWALEntry
    typealias CoreDataEntity = CDTransferWALEntry

    var entityIdentifierFieldName: String { #keyPath(CDTransferWALEntry.identifier) }

    func transform(entity: CDTransferWALEntry) throws -> TransferWALEntry {
        guard
            let identifierString = entity.identifier,
            let id = UUID(uuidString: identifierString)
        else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDTransferWALEntry.identifier))
        }
        guard let inputCoinIdsJSON = entity.inputCoinIds else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDTransferWALEntry.inputCoinIds))
        }
        guard let inputVoucherIdsJSON = entity.inputVoucherIds else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDTransferWALEntry.inputVoucherIds))
        }
        guard let expectedIndicesJSON = entity.expectedCoinIndices else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDTransferWALEntry.expectedCoinIndices))
        }

        let decoder = JSONDecoder()
        let inputCoinIds = try decoder.decode(
            [String].self,
            from: Data(inputCoinIdsJSON.utf8)
        )
        let inputVoucherIds = try decoder.decode(
            [String].self,
            from: Data(inputVoucherIdsJSON.utf8)
        )
        let expectedIndices = try decoder.decode(
            [UInt32].self,
            from: Data(expectedIndicesJSON.utf8)
        )

        let expectedVoucherIndices: [UInt32] =
            if let json = entity.expectedVoucherIndices {
                try decoder.decode([UInt32].self, from: Data(json.utf8))
            } else {
                []
            }

        // `checkpointBlockNumber` uses -1 as sentinel for `.pending`.
        // Both number and hash must be present for `.known`; fall back to `.pending` otherwise.
        let checkpointBlockNumber = entity.checkpointBlockNumber
        let checkpointBlock: CheckpointBlock =
            if checkpointBlockNumber != -1,
            let blockHash = entity.checkpointBlockHash,
            !blockHash.isEmpty {
                .known(
                    number: UInt32(bitPattern: checkpointBlockNumber),
                    hash: blockHash
                )
            } else {
                .pending
            }

        let operationType = TransferOperationType(rawValue: Int(entity.operationType)) ?? .intoCoins

        return TransferWALEntry(
            id: id,
            operationType: operationType,
            inputCoinIds: inputCoinIds,
            inputVoucherIds: inputVoucherIds,
            expectedCoinIndices: expectedIndices,
            expectedVoucherIndices: expectedVoucherIndices,
            checkpointBlock: checkpointBlock,
            mortality: UInt32(bitPattern: entity.mortality),
            createdAt: entity.createdAt ?? Date()
        )
    }

    func populate(
        entity: CDTransferWALEntry,
        from model: TransferWALEntry,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.id.uuidString
        entity.operationType = Int16(model.operationType.rawValue)

        let encoder = JSONEncoder()
        entity.inputCoinIds = try String(
            data: encoder.encode(model.inputCoinIds),
            encoding: .utf8
        )
        entity.inputVoucherIds = try String(
            data: encoder.encode(model.inputVoucherIds),
            encoding: .utf8
        )
        entity.expectedCoinIndices = try String(
            data: encoder.encode(model.expectedCoinIndices),
            encoding: .utf8
        )
        entity.expectedVoucherIndices = try String(
            data: encoder.encode(model.expectedVoucherIndices),
            encoding: .utf8
        )

        switch model.checkpointBlock {
        case .pending:
            entity.checkpointBlockNumber = -1
            entity.checkpointBlockHash = nil
        case let .known(number, hash):
            entity.checkpointBlockNumber = Int32(bitPattern: number)
            entity.checkpointBlockHash = hash
        }

        entity.mortality = Int32(bitPattern: model.mortality)
        entity.createdAt = model.createdAt
    }
}

/// Partial mapper that updates only `extrinsicHash` and `checkpointBlock` on an existing `CDTransferWALEntry`.
///
/// Use with a repository dedicated to hash/checkpoint updates to avoid re-encoding coin/voucher arrays.
/// Do NOT use for initial saves — missing fields will be left nil.
final class TransferWALUpdateMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case noExistingEntity
    }

    typealias DataProviderModel = TransferWALEntry
    typealias CoreDataEntity = CDTransferWALEntry

    var entityIdentifierFieldName: String { #keyPath(CDTransferWALEntry.identifier) }

    func transform(entity: CDTransferWALEntry) throws -> TransferWALEntry {
        try TransferWALMapper().transform(entity: entity)
    }

    func populate(
        entity: CDTransferWALEntry,
        from model: TransferWALEntry,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.noExistingEntity
        }

        switch model.checkpointBlock {
        case .pending:
            entity.checkpointBlockNumber = -1
            entity.checkpointBlockHash = nil
        case let .known(number, hash):
            entity.checkpointBlockNumber = Int32(bitPattern: number)
            entity.checkpointBlockHash = hash
        }
    }
}
