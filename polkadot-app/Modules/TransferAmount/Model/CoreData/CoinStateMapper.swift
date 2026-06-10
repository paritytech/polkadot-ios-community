import Foundation
import CoreData
import Coinage
import Operation_iOS

final class CoinStateMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Coin
    typealias CoreDataEntity = CDCoin

    private lazy var baseMapper = CoinMapper()
}

extension CoinStateMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        try baseMapper.transform(entity: entity)
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using _: NSManagedObjectContext
    ) throws {
        entity.state =
            switch model.state {
            case .spent: 0
            case .available: 1
            case .recycling: 2
            case .pendingTransfer: 3
            }
    }
}
