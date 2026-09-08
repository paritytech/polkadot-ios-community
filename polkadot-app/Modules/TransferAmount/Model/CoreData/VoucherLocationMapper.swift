import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Writes only the location-sync fields (`onChainState`, `recyclerIndex`, `recyclerMembers` and the
/// two fungibility scores) onto an existing `CDVoucher`, leaving every other column untouched.
///
/// Write-only in the sense that it never transforms an entity back into a model. It does read
/// `recyclerIndex` and `maxFungibilityCaptured` — the ceiling is frozen for as long as the voucher
/// stays in one ring, so the write has to know which ring was stored before it and whether a
/// ceiling has actually been recorded for that ring yet.
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

        let enteredNewRing = entity.recyclerIndex != previousRecyclerIndex

        populateFungibility(entity: entity, from: model, enteredNewRing: enteredNewRing)
    }
}

private extension VoucherLocationMapper {
    /// The current score tracks every reading; the ceiling is captured once per ring membership —
    /// on entry, and again only if the voucher is ever placed in a different ring.
    ///
    /// Capture is tracked explicitly rather than inferred. Inferring it from the stored score being
    /// zero would mistake a fully drained ring's genuine zero for "not recorded"; inferring it from
    /// the ring index changing would miss the case where the ring arrives before its score, leaving
    /// the ceiling unset for good — including for every voucher already in a ring when this column
    /// was added.
    func populateFungibility(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        enteredNewRing: Bool
    ) {
        if let fungibility = model.recyclerFungibility {
            entity.recyclerFungibility = Int16(fungibility)
        }

        if enteredNewRing {
            entity.maxFungibilityCaptured = false
        }

        guard let ceiling = model.maxRecyclerFungibility, !entity.maxFungibilityCaptured else {
            return
        }

        entity.maxRecyclerFungibility = Int16(ceiling)
        entity.maxFungibilityCaptured = true
    }
}
