import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Writes only the location-sync fields (`onChainState`, `recyclerIndex`, `recyclerMembers`,
/// `enteredAt` and the two fungibility scores) onto an existing `CDVoucher`, leaving every other
/// column untouched.
///
/// Write-only in the sense that it never transforms an entity back into a model. It does read
/// `recyclerIndex`, `enteredAt` and `maxFungibilityCaptured`: both the first confirmed inclusion
/// time and the frozen ceiling are held for as long as the voucher stays in one ring, so the write
/// has to know which ring was stored before it.
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

        // An unloaded verdict is reversible, so the ring columns it would otherwise clear are kept: a
        // fork that retracts it writes the same ring back and finds the inclusion time and ceiling intact.
        guard case .unloaded = model.remoteState else {
            populateLocation(entity: entity, from: model)
            return
        }

        entity.onChainState = Self.rawState(of: model.remoteState)
    }
}

private extension VoucherLocationMapper {
    func populateLocation(entity: CoreDataEntity, from model: DataProviderModel) {
        // Read before any write below: both the inclusion time and the ceiling are keyed on
        // whether this is the same ring the entity already held.
        let previousRecyclerIndex = entity.recyclerIndex
        let recycler: Voucher.Recycler? =
            if case let .inRecycler(recycler) = model.remoteState { recycler } else { nil }

        if let recycler {
            entity.enteredAt = previousRecyclerIndex == Int64(recycler.index)
                ? entity.enteredAt ?? recycler.enteredAt
                : recycler.enteredAt
            entity.recyclerIndex = Int64(recycler.index)
            entity.recyclerMembers = Int64(recycler.membersCount)
        } else {
            entity.enteredAt = nil
            entity.recyclerIndex = -1
            entity.recyclerMembers = 0
        }

        entity.onChainState = Self.rawState(of: model.remoteState)

        let enteredNewRing = entity.recyclerIndex != previousRecyclerIndex

        populateFungibility(entity: entity, from: model, enteredNewRing: enteredNewRing)
    }

    static func rawState(of state: Voucher.OnChainState) -> Int16 {
        switch state {
        case .unlocated: 0
        case .onboarding: 1
        case .inRecycler: 2
        case .unloaded: 3
        }
    }

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
