import Foundation
import CoreData
import Coinage
import Operation_iOS

final class CoinMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Coin
    typealias CoreDataEntity = CDCoin
}

extension CoinMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        let state: Coin.State =
            switch entity.state {
            case 1: .available
            case 2: .recycling
            case 3: .pendingTransfer
            default: .spent
            }

        let age = entity.age >= 0 ? entity.age : nil

        return Coin(
            exponent: entity.exponent,
            derivationIndex: UInt32(bitPattern: entity.derivationIndex),
            age: age,
            state: state
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.derivationIndex = Int32(bitPattern: model.derivationIndex)
        entity.exponent = model.exponent
        entity.age = model.age ?? -1
        entity.state =
            switch model.state {
            case .spent: 0
            case .available: 1
            case .recycling: 2
            case .pendingTransfer: 3
            }
    }
}
