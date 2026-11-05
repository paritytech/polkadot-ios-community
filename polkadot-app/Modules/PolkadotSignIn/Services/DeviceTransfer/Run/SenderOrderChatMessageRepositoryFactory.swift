import CoreData
import Foundation
import Operation_iOS

/// Keeps the old phone's order and moves the counter past it, so messages written here later still sort last.
final class SenderOrderChatMessageRepositoryFactory: ChatMessageRepositoryMaking {
    private let storageFacade: StorageFacadeProtocol
    private let orderAllocator: ChatMessageOrderAllocating

    init(
        storageFacade: StorageFacadeProtocol,
        orderAllocator: ChatMessageOrderAllocating = FileChatMessageOrderAllocator.shared
    ) {
        self.storageFacade = storageFacade
        self.orderAllocator = orderAllocator
    }

    var databaseService: CoreDataServiceProtocol {
        storageFacade.databaseService
    }

    func createRepository(forFilter filter: NSPredicate?) -> AnyDataProviderRepository<Chat.LocalMessage> {
        createRepository(forFilter: filter, sortDescriptors: [])
    }

    func createRepository(
        forFilter filter: NSPredicate?,
        sortDescriptors: [NSSortDescriptor]
    ) -> AnyDataProviderRepository<Chat.LocalMessage> {
        AnyDataProviderRepository(
            storageFacade.createRepository(
                filter: filter,
                sortDescriptors: sortDescriptors,
                mapper: AnyCoreDataMapper(SenderOrderChatMessageMapper(orderAllocator: orderAllocator))
            )
        )
    }
}

private final class SenderOrderChatMessageMapper {
    typealias DataProviderModel = Chat.LocalMessage
    typealias CoreDataEntity = CDChatMessage

    private let messageMapper: ChatMessageEntityMapper
    private let orderAllocator: ChatMessageOrderAllocating

    init(orderAllocator: ChatMessageOrderAllocating) {
        messageMapper = ChatMessageEntityMapper(orderAllocator: orderAllocator)
        self.orderAllocator = orderAllocator
    }

    var entityIdentifierFieldName: String {
        messageMapper.entityIdentifierFieldName
    }
}

extension SenderOrderChatMessageMapper: CoreDataMapperProtocol {
    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        try messageMapper.transform(entity: entity)
    }

    func populate(entity: CoreDataEntity, from model: DataProviderModel, using context: NSManagedObjectContext) throws {
        try messageMapper.populate(
            entity: entity,
            from: model,
            inheritingOrder: Int64(bitPattern: model.order),
            using: context
        )
        try orderAllocator.raiseOrder(atLeast: model.order)
    }
}
