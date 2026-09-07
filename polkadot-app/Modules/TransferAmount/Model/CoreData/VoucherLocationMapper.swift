import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Writes only the location-sync fields (`onChainState`, `recyclerIndex`, `recyclerMembers` and the
/// two fungibility scores) onto an existing `CDVoucher`, leaving every other column untouched.
///
/// Write-only in the sense that it never transforms an entity back into a model. It does read
/// `recyclerIndex` — the ceiling is frozen for as long as the voucher stays in one ring, so the
/// write has to know which ring was stored before it.
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

        let previousRecyclerIndex = entity.recyclerIndex

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

        // The ceiling describes one particular ring, so it is captured when the voucher enters a
        // ring and again only if it is ever placed in a different one — never on a refresh of the
        // ring it is already in.
        //
        // Keyed on the ring index rather than on the stored score being zero: zero is a legitimate
        // reading for a fully drained ring, and treating it as "nothing captured yet" would let a
        // later, more favourable reading overwrite a ceiling that is supposed to be frozen.
        if let ceiling = model.maxRecyclerFungibility, entity.recyclerIndex != previousRecyclerIndex {
            entity.maxRecyclerFungibility = Int16(ceiling)
        }
    }
}
