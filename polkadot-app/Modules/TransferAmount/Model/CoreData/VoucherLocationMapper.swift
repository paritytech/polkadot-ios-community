import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Populates Voucher pending and recycler info only
final class VoucherLocationMapper {
    enum MappingError: Error {
        case noExistingRequest
    }

    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Voucher
    typealias CoreDataEntity = CDVoucher

    private lazy var baseMapper = VoucherMapper()
}

extension VoucherLocationMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        try baseMapper.transform(entity: entity)
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.noExistingRequest
        }
        entity.recyclerIndex = model.recycler.flatMap { Int64($0.index) } ?? -1

        entity.state =
            switch model.remoteState {
            case .unlocated: 0
            case .onboarding: 1
            case .inRecycler: 2
            }

        entity.privacy =
            switch model.privacy {
            case .full: 1
            case .degraded: 0
            }
    }
}
