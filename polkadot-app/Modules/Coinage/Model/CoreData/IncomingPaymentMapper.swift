import BigInt
import Coinage
import CoreData
import Foundation
import Operation_iOS

/// Maps between ``IncomingPayment`` domain models and `CDIncomingPayment` CoreData entities.
///
/// The record is keyed by its `groupId` (`"productId:paymentId"`) as `identifier`. Secret material is
/// serialized as a JSON array of the source's secret keys (base64), with `sourceType` as the shape
/// discriminator needed to reconstruct the source.
final class IncomingPaymentMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = IncomingPayment
    typealias CoreDataEntity = CDIncomingPayment

    var entityIdentifierFieldName: String { #keyPath(CDIncomingPayment.identifier) }

    func transform(entity: CDIncomingPayment) throws -> IncomingPayment {
        guard let paymentId = entity.paymentId,
              let productId = entity.productId,
              let amountString = entity.amount,
              let sourceTypeRaw = entity.sourceType,
              let sourceType = IncomingPaymentSourceType(rawValue: sourceTypeRaw),
              let materialData = entity.sourceMaterial,
              let createdAt = entity.createdAt
        else {
            throw IncomingPaymentMapperError.missingRequiredField
        }

        let secretKeys = try JSONDecoder().decode([Data].self, from: materialData)
        let source = try IncomingPaymentSource(sourceType: sourceType, secretKeys: secretKeys)

        return IncomingPayment(
            paymentId: paymentId,
            productId: productId,
            source: source,
            amount: BigUInt(amountString) ?? 0,
            processed: entity.processed,
            createdAt: createdAt
        )
    }

    func populate(
        entity: CDIncomingPayment,
        from model: IncomingPayment,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.groupId
        entity.paymentId = model.paymentId
        entity.productId = model.productId
        entity.amount = String(model.amount)
        entity.sourceType = model.source.sourceType.rawValue
        entity.sourceMaterial = try JSONEncoder().encode(model.source.secretKeys)
        entity.processed = model.processed
        entity.createdAt = model.createdAt
    }
}

/// Write-only mapper that flips only `processed` on an existing `CDIncomingPayment`, leaving every
/// other column untouched (mirrors `CoinPresenceMapper`). Never reads a payment back, so marking a
/// payment complete does not fetch-modify-save the whole record (see CLAUDE.md).
final class IncomingPaymentProcessedMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case missingPayment
    }

    typealias DataProviderModel = IncomingPaymentProcessedUpdate
    typealias CoreDataEntity = CDIncomingPayment

    var entityIdentifierFieldName: String { #keyPath(CDIncomingPayment.identifier) }

    func transform(entity _: CDIncomingPayment) throws -> IncomingPaymentProcessedUpdate {
        throw CoreDataMapperError.unsupported
    }

    func populate(
        entity: CDIncomingPayment,
        from model: IncomingPaymentProcessedUpdate,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.missingPayment
        }
        entity.processed = model.processed
    }
}

private enum IncomingPaymentMapperError: Error {
    case missingRequiredField
}
