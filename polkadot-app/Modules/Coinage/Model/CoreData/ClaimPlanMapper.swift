import Operation_iOS
import CoreData
import Coinage
import SubstrateSdk
import BigInt

/// Maps between ``ClaimPlan`` domain models and `CDClaimPlan` CoreData entities.
///
/// Entries are serialized as a SCALE blob via ``CodableClaimPlanEntry`` to avoid
/// a separate CoreData entity for the one-to-many relationship.
final class ClaimPlanMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = ClaimPlan
    typealias CoreDataEntity = CDClaimPlan

    var entityIdentifierFieldName: String { #keyPath(CDClaimPlan.identifier) }

    func transform(entity: CDClaimPlan) throws -> ClaimPlan {
        guard let memoKey = entity.memoKey,
              let messageId = entity.messageId
        else {
            throw ClaimPlanMapperError.missingRequiredField
        }

        let decoder = entity.entriesData.flatMap { try? ScaleDecoder(data: $0) }
        let decoded = decoder.flatMap { try? [CodableClaimPlanEntry](scaleDecoder: $0) } ?? []
        let entries: [ClaimPlanEntry] = decoded.map {
            ClaimPlanEntry(
                entryIndex: $0.entryIndex,
                destinationCoin: Coin(
                    exponent: $0.destinationExponent,
                    derivationIndex: $0.destinationDerivationIndex,
                    age: nil
                )
            )
        }

        let status = ClaimPlan.Status(rawValue: Int(entity.status)) ?? .processing
        let totalValue = entity.totalValue.flatMap { BigUInt($0) } ?? 0
        let claimedAmount = entity.claimedAmount.flatMap { BigUInt($0) }

        return ClaimPlan(
            memoKey: memoKey,
            messageId: messageId,
            entries: entries,
            status: status,
            totalValue: totalValue,
            claimedAmount: claimedAmount
        )
    }

    func populate(
        entity: CDClaimPlan,
        from model: ClaimPlan,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.memoKey = model.memoKey
        entity.messageId = model.messageId
        entity.status = Int16(model.status.rawValue)
        entity.totalValue = String(model.totalValue)
        entity.claimedAmount = model.claimedAmount.map { String($0) }

        let codableEntries = model.entries.map {
            CodableClaimPlanEntry(
                entryIndex: $0.entryIndex,
                destinationExponent: $0.destinationCoin.exponent,
                destinationDerivationIndex: $0.destinationCoin.derivationIndex
            )
        }
        let encoder = ScaleEncoder()
        try codableEntries.encode(scaleEncoder: encoder)
        entity.entriesData = encoder.encode()
    }
}

/// Partial mapper that updates only `status` and `claimedAmount` on an existing `CDClaimPlan`.
///
/// Use this with a repository dedicated to status updates to avoid re-encoding entries.
/// Do NOT use for initial saves — missing fields will be left nil.
final class ClaimPlanStatusMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case noExistingEntity
    }

    typealias DataProviderModel = ClaimPlan
    typealias CoreDataEntity = CDClaimPlan

    var entityIdentifierFieldName: String { #keyPath(CDClaimPlan.identifier) }

    func transform(entity: CDClaimPlan) throws -> ClaimPlan {
        try ClaimPlanMapper().transform(entity: entity)
    }

    func populate(
        entity: CDClaimPlan,
        from model: ClaimPlan,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.noExistingEntity
        }
        entity.status = Int16(model.status.rawValue)
        entity.claimedAmount = model.claimedAmount.map { String($0) }
    }
}

private struct CodableClaimPlanEntry: ScaleCodable {
    let entryIndex: Int
    let destinationExponent: Int16
    let destinationDerivationIndex: UInt32

    init(
        entryIndex: Int,
        destinationExponent: Int16,
        destinationDerivationIndex: UInt32
    ) {
        self.entryIndex = entryIndex
        self.destinationExponent = destinationExponent
        self.destinationDerivationIndex = destinationDerivationIndex
    }

    init(scaleDecoder: any ScaleDecoding) throws {
        entryIndex = try Int(Int16(scaleDecoder: scaleDecoder))
        destinationExponent = try Int16(scaleDecoder: scaleDecoder)
        destinationDerivationIndex = try UInt32(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try Int16(entryIndex).encode(scaleEncoder: scaleEncoder)
        try destinationExponent.encode(scaleEncoder: scaleEncoder)
        try destinationDerivationIndex.encode(scaleEncoder: scaleEncoder)
    }
}

private enum ClaimPlanMapperError: Error {
    case missingRequiredField
}
