import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

protocol ChatRequestDeliveryStoring {
    /// Still ours to deliver: outgoing, its welcome message unsent, and still the contact's request — the peer's
    /// own request may have been accepted, or the contact removed, in the meantime.
    func isAwaitingDelivery(requestId: String) async throws -> Bool

    /// Marks the welcome message sent and records which period's account delivered it, in one write.
    func markDelivered(requestId: String, anonymousPeriod: UInt32) async throws

    func markFailed(requestId: String) async throws
}

final class ChatRequestDeliveryStore {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }
}

extension ChatRequestDeliveryStore: ChatRequestDeliveryStoring {
    func isAwaitingDelivery(requestId: String) async throws -> Bool {
        try await databaseService.performRead { context in
            guard let request = try Self.fetchRequest(requestId, in: context) else { return false }

            return request.status == Chat.RequestStatus.outgoing.rawValue &&
                request.message?.status == Chat.LocalMessage.Status.outgoing(.new).rawValue &&
                request.contact?.chatRequest == request
        }
    }

    func markDelivered(requestId: String, anonymousPeriod: UInt32) async throws {
        try await databaseService.performWrite { context in
            guard let request = try Self.fetchRequest(requestId, in: context) else { return }

            request.anonymousDeliveryPeriod = NSNumber(value: Int32(bitPattern: anonymousPeriod))
            request.message?.status = Chat.LocalMessage.Status.outgoing(.sent).rawValue
            request.message?.touchParent()
            request.touchParent()
        }
    }

    func markFailed(requestId: String) async throws {
        try await databaseService.performWrite { context in
            guard let request = try Self.fetchRequest(requestId, in: context) else { return }

            request.message?.status = Chat.LocalMessage.Status.outgoing(.failed).rawValue
            request.message?.touchParent()
            request.touchParent()
        }
    }
}

private extension ChatRequestDeliveryStore {
    static func fetchRequest(_ requestId: String, in context: NSManagedObjectContext) throws -> CDChatRequest? {
        let fetchRequest = CDChatRequest.fetchRequest()
        fetchRequest.predicate = .chatRequestById(requestId)
        fetchRequest.fetchLimit = 1

        return try context.fetch(fetchRequest).first
    }
}
