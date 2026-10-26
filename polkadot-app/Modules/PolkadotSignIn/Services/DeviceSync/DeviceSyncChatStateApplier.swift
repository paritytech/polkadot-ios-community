import CoreData
import Foundation
import Operation_iOS
import Products
import StructuredConcurrency
import SubstrateSdk

protocol DeviceSyncChatStateApplying {
    func applyBlockStates(_ states: [Chat.DeviceSyncChatBlockState]) async throws
    func applyIncomingRequests(_ requests: [Chat.DeviceSyncIncomingChatRequest]) async throws
    func applyIncomingStatusUpdates(_ updates: [Chat.DeviceSyncIncomingRequestStatusUpdate]) async throws
    func applyOutgoingRequests(_ requests: [Chat.DeviceSyncOutgoingChatRequest]) async throws
    func applyOutgoingStatusUpdates(_ updates: [Chat.DeviceSyncOutgoingRequestStatusUpdate]) async throws
}

/// Writes block state and chat requests received from a sibling. Nothing here stamps `modifiedAt`: that would send
/// every applied change straight back to the sibling it came from.
final class DeviceSyncChatStateApplier {
    private let databaseService: CoreDataServiceProtocol
    private let remoteContactResolver: RemoteContactResolving
    private let tldProvider: DotNsTldProviding
    private let logger: LoggerProtocol

    init(
        databaseService: CoreDataServiceProtocol,
        remoteContactResolver: RemoteContactResolving,
        tldProvider: DotNsTldProviding,
        logger: LoggerProtocol
    ) {
        self.databaseService = databaseService
        self.remoteContactResolver = remoteContactResolver
        self.tldProvider = tldProvider
        self.logger = logger
    }
}

extension DeviceSyncChatStateApplier: DeviceSyncChatStateApplying {
    func applyBlockStates(_ states: [Chat.DeviceSyncChatBlockState]) async throws {
        let logger = logger

        try await databaseService.performWrite { context in
            for state in states {
                guard case let .contact(accountId) = state.chatId else { continue }

                guard let contact: CDChatContact = try context.first(for: .contact(for: accountId)) else {
                    logger.debug("No contact for synced block state, skipping")
                    continue
                }

                if contact.isBlocked != state.blocked {
                    contact.isBlocked = state.blocked
                }
            }
        }
    }

    func applyIncomingRequests(_ requests: [Chat.DeviceSyncIncomingChatRequest]) async throws {
        try await upsertIncomingRows(requests)
    }

    /// Only updates requests already stored: a status alone can't make a complete row.
    func applyIncomingStatusUpdates(_ updates: [Chat.DeviceSyncIncomingRequestStatusUpdate]) async throws {
        try await databaseService.performWrite { context in
            for update in updates {
                guard
                    let entity: CDChatRequest = try context.first(for: .chatRequestById(update.requestId)),
                    entity.contact == nil
                else {
                    continue
                }

                entity.status = update.status.localStatus.rawValue
            }
        }
    }

    func applyOutgoingRequests(_ requests: [Chat.DeviceSyncOutgoingChatRequest]) async throws {
        for request in requests where request.status == .pending {
            try await applyPendingOutgoing(request)
        }
    }

    func applyOutgoingStatusUpdates(_ updates: [Chat.DeviceSyncOutgoingRequestStatusUpdate]) async throws {
        let cancelledIds = updates.filter { $0.status == .cancelled }.map(\.requestId)

        guard !cancelledIds.isEmpty else { return }

        try await databaseService.performWrite { context in
            for requestId in cancelledIds {
                guard
                    let request: CDChatRequest = try context.first(for: .chatRequestById(requestId)),
                    let contact = request.contact,
                    contact.chatRequest == request
                else {
                    continue
                }

                if let chat = contact.chat {
                    context.delete(chat)
                }
                context.delete(contact)
            }
        }
    }
}

private extension DeviceSyncChatStateApplier {
    /// Rows without a contact link, so discovery skips the request when its statement is found again. A local
    /// request still linked to its contact belongs to the local accept or decline flow and is left as it is.
    func upsertIncomingRows(_ rows: [Chat.DeviceSyncIncomingChatRequest]) async throws {
        try await databaseService.performWrite { context in
            for row in rows {
                let existing: CDChatRequest? = try context.first(for: .chatRequestById(row.requestId))

                guard existing?.contact == nil else { continue }

                let entity = try existing ?? context.insertNew(CDChatRequest.self)
                entity.identifier = row.requestId
                entity.status = row.status.localStatus.rawValue
                entity.contactId = row.peer.toHex()
                entity.timestamp = Int64(bitPattern: row.timestamp)
            }
        }
    }

    func applyPendingOutgoing(_ request: Chat.DeviceSyncOutgoingChatRequest) async throws {
        let peer = request.peer
        let hasContact = try await databaseService.performRead { context in
            let contact: CDChatContact? = try context.first(for: .contact(for: peer))
            return contact != nil
        }

        guard !hasContact else { return }

        guard let remoteContact = try await remoteContactResolver.fetch(by: peer) else {
            logger.warning("No on-chain data for a synced outgoing request's peer, skipping")
            return
        }

        let newOutgoing = try ChatRequest.NewOutgoing(
            message: Chat.RequestMessage(
                messageId: request.requestId,
                timestamp: request.timestamp,
                content: request.content
            ),
            remoteContact: remoteContact,
            pushId: nil,
            ownKeyId: .main(tldProvider: tldProvider)
        )

        try await databaseService.performWrite { context in
            let entity = try context.insertNew(CDChatRequest.self)
            try NewOutgoingChatRequestMapper().populate(entity: entity, from: newOutgoing, using: context)

            // The request was already published by the sibling: renew it rather than send it as new.
            entity.modifiedAt = nil
            entity.message?.status = Chat.LocalMessage.Status.outgoing(.sent).rawValue
        }
    }
}

private extension Chat.DeviceSyncIncomingRequestStatus {
    var localStatus: Chat.RequestStatus {
        switch self {
        case .pending: .incoming(.new)
        case .accepted: .incoming(.accepted)
        case .declined: .incoming(.declined)
        }
    }
}
