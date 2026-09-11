import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Updates location fields while preserving the first confirmed inclusion time in the same ring.
final class VoucherLocationMapper {
    enum MappingError: Error {
        case missingVoucher
    }

    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = VoucherLocationUpdate
    typealias CoreDataEntity = CDVoucher
}

extension VoucherLocationMapper: CoreDataMapperProtocol {
    func transform(entity _: CoreDataEntity) throws -> DataProviderModel {
        throw CoreDataMapperError.unsupported
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.missingVoucher
        }

        entity.enteredAt =
            switch model.remoteState {
            case let .inRecycler(recycler):
                entity.recyclerIndex == Int64(recycler.index)
                    ? entity.enteredAt ?? recycler.enteredAt
                    : recycler.enteredAt
            case .unlocated,
                 .onboarding: nil
            }

        entity.recyclerIndex =
            switch model.remoteState {
            case let .inRecycler(recycler): Int64(recycler.index)
            case .unlocated,
                 .onboarding: -1
            }

        entity.recyclerMembers =
            switch model.remoteState {
            case let .inRecycler(recycler): Int64(recycler.membersCount)
            case .unlocated,
                 .onboarding: 0
            }

        entity.onChainState =
            switch model.remoteState {
            case .unlocated: 0
            case .onboarding: 1
            case .inRecycler: 2
            }
    }
}
