import Foundation
import Operation_iOS
import Foundation_iOS
import CoreData
import SubstrateSdk

final class CancelIncomingChatRequestMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = ChatRequest.CancelIncoming
    typealias CoreDataEntity = CDChatRequest
}

extension CancelIncomingChatRequestMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case noExistingRequest
        case chatHasConversation
    }

    func transform(entity _: CoreDataEntity) throws -> DataProviderModel {
        throw CoreDataMapperError.unsupported
    }

    func populate(
        entity: CoreDataEntity,
        from _: DataProviderModel,
        using context: NSManagedObjectContext
    ) throws {
        guard let contactId = try entity.contactId?.fromHex() else {
            throw MappingError.noExistingRequest
        }

        let isAccepted = entity.status == Chat.RequestStatus.incoming(.accepted).rawValue
        if isAccepted, try context.chatHasConversation(withContact: contactId) {
            throw MappingError.chatHasConversation
        }

        entity.status = Chat.RequestStatus.incoming(.cancelled).rawValue
        context.deleteChatContactAndChat(for: contactId)
    }
}

extension ChatRequest.CancelIncoming: Identifiable {
    var identifier: String {
        requestId
    }
}
