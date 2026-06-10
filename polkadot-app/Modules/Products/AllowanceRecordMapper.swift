import CoreData
import Foundation
import Operation_iOS
import Individuality

final class AllowanceRecordMapper: CoreDataMapperProtocol {
    var entityIdentifierFieldName: String { #keyPath(CDAllowanceRecord.identifier) }

    typealias DataProviderModel = AllowanceRecord
    typealias CoreDataEntity = CDAllowanceRecord

    func transform(entity: CDAllowanceRecord) throws -> AllowanceRecord {
        guard let accountId = entity.accountId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDAllowanceRecord.accountId))
        }
        guard let allocatedAt = entity.allocatedAt else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDAllowanceRecord.allocatedAt))
        }
        return AllowanceRecord(accountId: accountId, allocatedAt: allocatedAt)
    }

    func populate(
        entity: CDAllowanceRecord,
        from model: AllowanceRecord,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.accountId = model.accountId
        entity.allocatedAt = model.allocatedAt
    }
}
