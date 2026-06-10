import Foundation
import CoreData
import Coinage
import Operation_iOS

final class VoucherMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Voucher
    typealias CoreDataEntity = CDVoucher
}

extension VoucherMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        guard let allocatedAt = entity.allocatedAt else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.allocatedAt)
            )
        }

        guard let readyAt = entity.readyAt else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.readyAt)
            )
        }

        let recycler: Voucher.Recycler? =
            if entity.recyclerIndex >= 0 {
                Voucher.Recycler(
                    index: UInt32(entity.recyclerIndex)
                )
            } else {
                nil
            }

        let state: Voucher.OnChainState =
            if entity.state == 1 {
                .onboarding
            } else if entity.state == 2, let recycler {
                .inRecycler(recycler)
            } else {
                .unlocated
            }

        let localState: Voucher.State =
            switch entity.localState {
            case 1: .pendingTransfer
            case 2: .pendingOnboarding
            default: .available
            }

        let privacy: VoucherPrivacyLevel = entity.privacy == 1 ? .full : .degraded

        return Voucher(
            exponent: entity.exponent,
            derivationIndex: UInt32(entity.derivationIndex),
            allocatedAt: allocatedAt,
            readyAt: readyAt,
            remoteState: state,
            localState: localState,
            privacy: privacy
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.derivationIndex = Int64(model.derivationIndex)
        entity.exponent = model.exponent
        entity.readyAt = model.readyAt
        entity.allocatedAt = model.allocatedAt
        entity.recyclerIndex = model.recycler.flatMap { Int64($0.index) } ?? -1

        entity.state =
            switch model.remoteState {
            case .unlocated: 0
            case .onboarding: 1
            case .inRecycler: 2
            }

        entity.localState =
            switch model.localState {
            case .available: 0
            case .pendingTransfer: 1
            case .pendingOnboarding: 2
            }

        entity.privacy =
            switch model.privacy {
            case .full: 1
            case .degraded: 0
            }
    }
}
