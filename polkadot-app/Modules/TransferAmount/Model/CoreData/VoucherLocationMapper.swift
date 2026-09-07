import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Writes only the location-sync fields (`onChainState`, `recyclerIndex`, `recyclerMembers` and the
/// two fungibility scores) onto an existing `CDVoucher`, leaving every other column untouched.
///
/// Write-only in the sense that it never transforms an entity back into a model. It does read
/// `maxRecyclerFungibility` — the ceiling is frozen the first time the voucher is seen in a ring, so
/// the write has to know whether one is already stored.
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

        if let fungibility = model.recyclerFungibility {
            entity.recyclerFungibility = Int16(fungibility)
        }

        // Zero doubles as "no ceiling recorded yet": a voucher is minted before the chain assigns it
        // a ring, so there is nothing to compute one from until it lands in one.
        if let ceiling = model.maxRecyclerFungibility, entity.maxRecyclerFungibility == 0 {
            entity.maxRecyclerFungibility = Int16(ceiling)
        }
    }
}
