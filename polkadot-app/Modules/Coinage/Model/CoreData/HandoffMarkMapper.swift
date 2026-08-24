import Foundation
import CoreData
import Coinage
import Operation_iOS

/// A record that an asset was given to a peer.
///
/// Insert-only: `ownCoinInputs` asks whether an asset has *ever* carried a mark, so the fact
/// must survive any later state change.
struct HandoffMark: Equatable {
    let identifier: String
    let createdAt: Date
}

extension HandoffMark: Operation_iOS.Identifiable {}

final class HandoffMarkMapper: CoreDataMapperProtocol {
    typealias DataProviderModel = HandoffMark
    typealias CoreDataEntity = CDHandoffMark

    var entityIdentifierFieldName: String { #keyPath(CDHandoffMark.identifier) }

    func transform(entity: CDHandoffMark) throws -> HandoffMark {
        guard let identifier = entity.identifier else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CDHandoffMark.identifier)
            )
        }
        return HandoffMark(identifier: identifier, createdAt: entity.createdAt ?? Date())
    }

    func populate(
        entity: CDHandoffMark,
        from model: HandoffMark,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.createdAt = model.createdAt
    }
}
