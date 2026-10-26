import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt

protocol DeviceSyncChatStateCollecting {
    /// Block state and chat requests: everything on a full collection (`cutoff == nil`), otherwise what was
    /// modified after `cutoff`. Pending outgoing requests come first, since applying them creates their contacts.
    func collect(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity]
}

struct DeviceSyncChatStateCollector {
    private let databaseService: CoreDataServiceProtocol

    init(databaseService: CoreDataServiceProtocol) {
        self.databaseService = databaseService
    }
}

extension DeviceSyncChatStateCollector: DeviceSyncChatStateCollecting {
    func collect(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity] {
        try await databaseService.performRead { context in
            let outgoing = try Self.collectOutgoingRequests(after: cutoff, in: context)
            let blockStates = try Self.collectBlockStates(after: cutoff, in: context)
            let incoming = try Self.collectIncomingRequests(after: cutoff, in: context)

            return [
                outgoing.added.isEmpty ? nil : .outgoingRequestsAdded(outgoing.added),
                blockStates.isEmpty ? nil : .chatsBlocked(blockStates),
                incoming.isEmpty ? nil : .incomingRequestsAdded(incoming),
                outgoing.updated.isEmpty ? nil : .outgoingRequestsStatusUpdated(outgoing.updated)
            ].compactMap { $0 }
        }
    }
}

private extension DeviceSyncChatStateCollector {
    static func collectBlockStates(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncChatBlockState] {
        let predicate = cutoff.map { modified(after: $0) } ?? .blockedContacts()

        return try fetch(CDChatContact.self, matching: predicate, in: context).compactMap { contact in
            guard let accountId = try? contact.identifier?.fromHex() else { return nil }
            return Chat.DeviceSyncChatBlockState(chatId: .contact(accountId: accountId), blocked: contact.isBlocked)
        }
    }

    static func collectIncomingRequests(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> [Chat.DeviceSyncIncomingChatRequest] {
        let decided = NSPredicate(
            format: "%K IN %@",
            #keyPath(CDChatRequest.status),
            [Chat.RequestStatus.incoming(.accepted).rawValue, Chat.RequestStatus.incoming(.declined).rawValue]
        )
        let predicate = cutoff
            .map { NSCompoundPredicate(andPredicateWithSubpredicates: [decided, modified(after: $0)]) }
            ?? decided
        // Sent whole even when only the status changed: the receiver may not have the request yet, and a row
        // without its peer would break discovery's lookup by request id.
        return try fetch(CDChatRequest.self, matching: predicate, in: context)
            .compactMap { try makeIncomingRequest(from: $0, in: context) }
    }

    static func collectOutgoingRequests(
        after cutoff: Date?,
        in context: NSManagedObjectContext
    ) throws -> (added: [Chat.DeviceSyncOutgoingChatRequest], updated: [Chat.DeviceSyncOutgoingRequestStatusUpdate]) {
        let outgoing = NSPredicate(
            format: "%K == %d",
            #keyPath(CDChatRequest.status),
            Chat.RequestStatus.outgoing.rawValue
        )
        let predicate = cutoff
            .map { NSCompoundPredicate(andPredicateWithSubpredicates: [outgoing, modified(after: $0)]) }
            ?? outgoing

        var added: [Chat.DeviceSyncOutgoingChatRequest] = []
        var updated: [Chat.DeviceSyncOutgoingRequestStatusUpdate] = []

        for request in try fetch(CDChatRequest.self, matching: predicate, in: context) {
            guard let requestId = request.identifier else { continue }
            let status = try request.outgoingWireStatus(in: context)

            if status == .pending, let pending = try makeOutgoingRequest(from: request) {
                added.append(pending)
            } else if cutoff != nil, status != .pending {
                updated.append(Chat.DeviceSyncOutgoingRequestStatusUpdate(requestId: requestId, status: status))
            }
        }

        return (added, updated)
    }

    static func makeIncomingRequest(
        from request: CDChatRequest,
        in context: NSManagedObjectContext
    ) throws -> Chat.DeviceSyncIncomingChatRequest? {
        guard
            let requestId = request.identifier,
            let peer = try? request.contactId?.fromHex(),
            let status = request.incomingWireStatus
        else {
            return nil
        }

        let content = request.message.flatMap { try? $0.requestContent() }?.ensureV1()
        let peerDevice: CDChatRequestPeerDevice? = try context.first(
            for: NSPredicate(format: "%K == %@", #keyPath(CDChatRequestPeerDevice.requestId), requestId)
        )

        return Chat.DeviceSyncIncomingChatRequest(
            requestId: requestId,
            peer: peer,
            timestamp: UInt64(bitPattern: request.timestamp),
            status: status,
            peerDevice: peerDevice?.wireDevice(lastUpdate: UInt64(bitPattern: request.timestamp)),
            pushToken: content?.pushToken,
            welcomeMessage: content?.welcomeMessage
        )
    }

    static func makeOutgoingRequest(from request: CDChatRequest) throws -> Chat.DeviceSyncOutgoingChatRequest? {
        guard
            let requestId = request.identifier,
            let peer = try? request.contactId?.fromHex(),
            let content = try request.message?.requestContent()
        else {
            return nil
        }

        return Chat.DeviceSyncOutgoingChatRequest(
            requestId: requestId,
            peer: peer,
            timestamp: UInt64(bitPattern: request.timestamp),
            status: .pending,
            content: content
        )
    }

    static func modified(after date: Date) -> NSPredicate {
        NSPredicate(format: "modifiedAt > %@", date as NSDate)
    }

    static func fetch<Entity: NSManagedObject>(
        _: Entity.Type,
        matching predicate: NSPredicate,
        in context: NSManagedObjectContext
    ) throws -> [Entity] {
        let request = NSFetchRequest<Entity>(entityName: String(describing: Entity.self))
        request.predicate = predicate
        return try context.fetch(request)
    }
}

private extension CDChatRequest {
    var incomingWireStatus: Chat.DeviceSyncIncomingRequestStatus? {
        switch Chat.RequestStatus(rawValue: status) {
        case .incoming(.new): .pending
        case .incoming(.accepted): .accepted
        case .incoming(.declined): .declined
        case .outgoing,
             nil: nil
        }
    }

    /// Outgoing requests keep status 5 for good; what happened to them shows on the contact.
    func outgoingWireStatus(in context: NSManagedObjectContext) throws -> Chat.DeviceSyncOutgoingRequestStatus {
        if contact?.chatRequest == self {
            return .pending
        }

        guard let peer = try? contactId?.fromHex() else { return .cancelled }
        let peerContact: CDChatContact? = try context.first(for: .contact(for: peer))
        return peerContact == nil ? .cancelled : .accepted
    }
}

private extension CDChatRequestPeerDevice {
    func wireDevice(lastUpdate: UInt64) -> Chat.DeviceSyncWireDevice? {
        guard let statementAccountId, let encryptionPublicKey else { return nil }

        return Chat.DeviceSyncWireDevice(
            statementAccountId: statementAccountId,
            encryptionPublicKey: encryptionPublicKey,
            status: .active,
            lastUpdate: lastUpdate
        )
    }
}

private extension CDChatMessage {
    func requestContent() throws -> Chat.VersionedRequestContent? {
        let localMessage = try ChatMessageEntityMapper().transform(entity: self)
        return Chat.RequestMessage(localMessage: localMessage)?.content
    }
}
