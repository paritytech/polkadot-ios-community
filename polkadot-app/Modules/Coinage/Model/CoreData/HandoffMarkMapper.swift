import Foundation
import CoreData
import Coinage
import Operation_iOS

/// Local state of a handoff mark relative to statement-store submission.
///
/// `precommit` — the mark is written before the keys reach the transport; `commit` — the carrying
/// message has been submitted to the statement store.
enum HandoffMarkState: Int16 {
    case precommit = 0
    case commit = 1
}

/// A record that an asset was given to a peer.
///
/// Insert-only: `ownCoinInputs` asks whether an asset has *ever* carried a mark, so the fact
/// must survive any later state change.
struct HandoffMark: Equatable {
    let identifier: String
    let createdAt: Date
    var state: HandoffMarkState = .precommit
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
        return HandoffMark(
            identifier: identifier,
            createdAt: entity.createdAt ?? Date(),
            state: HandoffMarkState(rawValue: entity.state) ?? .precommit
        )
    }

    func populate(
        entity: CDHandoffMark,
        from model: HandoffMark,
        using context: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.createdAt = model.createdAt
        entity.state = model.state.rawValue
        // Linking the coin marks that coin row as changed, so its snapshot subscribers re-emit.
        entity.coin = AssetCoding.ownAsset(from: model.identifier)
            .flatMap { DurabilityAssetLinker.coin(for: $0, in: context) }
    }
}
