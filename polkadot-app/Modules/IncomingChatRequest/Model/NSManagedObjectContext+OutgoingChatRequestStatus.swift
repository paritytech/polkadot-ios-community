import CoreData
import Foundation

extension NSManagedObjectContext {
    /// Returns false when the request is not the contact's current request in the `oldState`.
    func transitionOutgoingRequest(
        _ requestId: String,
        from oldState: Chat.RequestStatus.Outgoing,
        to newState: Chat.RequestStatus.Outgoing
    ) throws -> Bool {
        let fetchRequest = CDChatRequest.fetchRequest()
        fetchRequest.predicate = .chatRequestById(requestId)
        fetchRequest.fetchLimit = 1

        guard
            let request = try fetch(fetchRequest).first,
            request.status == Chat.RequestStatus.outgoing(oldState).rawValue,
            request.contact?.chatRequest == request
        else {
            return false
        }

        request.status = Chat.RequestStatus.outgoing(newState).rawValue
        request.touchParent()
        return true
    }

    func revertCancellingOutgoingRequests() throws {
        let fetchRequest = CDChatRequest.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatRequest.status),
            Chat.RequestStatus.outgoing(.cancelling).rawValue
        )

        for request in try fetch(fetchRequest) {
            request.status = Chat.RequestStatus.outgoing(.pending).rawValue
            request.touchParent()
        }
    }
}
