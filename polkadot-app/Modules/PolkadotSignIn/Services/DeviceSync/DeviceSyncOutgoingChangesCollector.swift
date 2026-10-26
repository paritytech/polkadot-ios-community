import Foundation
import MessageExchangeKit
import Operation_iOS

struct DeviceSyncCollectedChanges {
    var entities: [Chat.DeviceSyncEntity]
    var timePoint: UInt64
}

struct DeviceSyncOutgoingChangesCollector {
    private let deviceRepositoryFactory: LocalDeviceRepositoryMaking
    private let contactRepositoryFactory: ChatContactRepositoryMaking
    private let messageRepositoryFactory: ChatMessageRepositoryMaking
    private let removedChatRepositoryFactory: RemovedChatRepositoryMaking
    private let chatStateCollector: DeviceSyncChatStateCollecting
    private let coinageStateCollector: DeviceSyncCoinageStateCollecting
    private let ownSignKeyIds: Set<String>

    init(
        deviceRepositoryFactory: LocalDeviceRepositoryMaking,
        contactRepositoryFactory: ChatContactRepositoryMaking,
        messageRepositoryFactory: ChatMessageRepositoryMaking,
        removedChatRepositoryFactory: RemovedChatRepositoryMaking,
        chatStateCollector: DeviceSyncChatStateCollecting,
        coinageStateCollector: DeviceSyncCoinageStateCollecting,
        ownSignKeyIds: Set<String>
    ) {
        self.deviceRepositoryFactory = deviceRepositoryFactory
        self.contactRepositoryFactory = contactRepositoryFactory
        self.messageRepositoryFactory = messageRepositoryFactory
        self.removedChatRepositoryFactory = removedChatRepositoryFactory
        self.chatStateCollector = chatStateCollector
        self.coinageStateCollector = coinageStateCollector
        self.ownSignKeyIds = ownSignKeyIds
    }

    func collectEntities(
        since checkpoint: UInt64?
    ) async throws -> DeviceSyncCollectedChanges {
        let timePoint = Date().toChatTimestamp()
        let cutoff = checkpoint.map { Date.fromChatTimestamp($0) }
        var entities: [Chat.DeviceSyncEntity] = []

        let deviceChanges = try await collectDeviceChanges(after: cutoff)
        let contactChanges = try await collectContactChanges(after: cutoff)
        let removedChatChanges = try await collectRemovedChatChanges(after: cutoff)
        let chatStateChanges = try await chatStateCollector.collect(after: cutoff)
        let messageChanges = try await collectMessageChanges(since: checkpoint)
        let coinageStateChanges = try await coinageStateCollector.collect(after: cutoff)

        entities.append(contentsOf: deviceChanges)
        entities.append(contentsOf: contactChanges)
        entities.append(contentsOf: removedChatChanges)
        entities.append(contentsOf: chatStateChanges)
        entities.append(contentsOf: messageChanges)
        entities.append(contentsOf: coinageStateChanges)

        return DeviceSyncCollectedChanges(
            entities: entities,
            timePoint: timePoint
        )
    }
}

struct DeviceTransferMessagePage {
    var messages: [Chat.DeviceSyncWireMessage]
    /// `nil` once the set is exhausted.
    var nextCursor: String?
}

protocol DeviceTransferChangesCollecting {
    /// Everything but messages and devices, changed after `checkpoint`.
    func collectStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity]

    /// Messages changed after `checkpoint` (and no later than `bound`), in message id order after `cursor`.
    /// Keying on the id keeps paging stable: an edit moves a message into the next round instead of shifting pages.
    func collectMessagePage(
        since checkpoint: UInt64?,
        upTo bound: UInt64?,
        after cursor: String?,
        limit: Int
    ) async throws -> DeviceTransferMessagePage

    func countMessages(since checkpoint: UInt64?, upTo bound: UInt64?) async throws -> Int
}

extension DeviceSyncOutgoingChangesCollector: DeviceTransferChangesCollecting {
    func collectStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity] {
        let cutoff = checkpoint.map { Date.fromChatTimestamp($0) }

        return try await collectContactChanges(after: cutoff)
            + collectRemovedChatChanges(after: cutoff)
            + chatStateCollector.collect(after: cutoff)
            + coinageStateCollector.collect(after: cutoff)
    }

    func collectMessagePage(
        since checkpoint: UInt64?,
        upTo bound: UInt64?,
        after cursor: String?,
        limit: Int
    ) async throws -> DeviceTransferMessagePage {
        let afterCursor = cursor.map { NSPredicate(format: "%K > %@", #keyPath(CDChatMessage.messageId), $0) }
        let predicates = [transferMessagesPredicate(since: checkpoint, upTo: bound), afterCursor].compactMap { $0 }

        let messages = try await messageRepositoryFactory
            .createRepository(
                forFilter: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
                sortDescriptors: [NSSortDescriptor(key: #keyPath(CDChatMessage.messageId), ascending: true)]
            )
            .fetchOperation(by: RepositorySliceRequest(offset: 0, count: limit, reversed: false), options: .init())
            .asyncExecute()

        return DeviceTransferMessagePage(
            messages: messages.compactMap { Chat.DeviceSyncWireMessage(from: $0) },
            nextCursor: messages.count < limit ? nil : messages.last?.messageId
        )
    }

    func countMessages(since checkpoint: UInt64?, upTo bound: UInt64?) async throws -> Int {
        try await messageRepositoryFactory
            .createRepository(forFilter: transferMessagesPredicate(since: checkpoint, upTo: bound))
            .fetchCountOperation()
            .asyncExecute()
    }
}

private extension DeviceSyncOutgoingChangesCollector {
    func collectDeviceChanges(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity] {
        let deviceFilter = cutoff.map { NSPredicate.devicesCreatedAfter($0) }
        let devices = try await deviceRepositoryFactory
            .createRepository(forFilter: deviceFilter)
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let wireDevices = devices.map { Chat.DeviceSyncWireDevice(from: $0) }
        return wireDevices.isEmpty ? [] : [.devices(wireDevices)]
    }

    func collectContactChanges(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity] {
        let predicates: [NSPredicate] = [
            cutoff.map { NSPredicate.contactsAcceptedAfter($0) },
            NSPredicate.acceptedContacts
        ].compactMap { $0 }

        let contacts = try await contactRepositoryFactory
            .createRepository(forFilter: NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let chatIds = contacts
            .filter { ownSignKeyIds.contains($0.ownKeyId.signKeyId) }
            .map { Chat.DeviceSyncChatId.contact(accountId: $0.accountId) }

        return chatIds.isEmpty ? [] : [.chatsAdded(chatIds)]
    }

    func collectRemovedChatChanges(after cutoff: Date?) async throws -> [Chat.DeviceSyncEntity] {
        let removedFilter = cutoff.map { NSPredicate.removedChatsAfter($0) }
        let removedChats = try await removedChatRepositoryFactory
            .createRepository(forFilter: removedFilter)
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let chatIds = removedChats.map { Chat.DeviceSyncChatId.contact(accountId: $0.accountId) }
        return chatIds.isEmpty ? [] : [.chatsRemoved(chatIds)]
    }

    func collectMessageChanges(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity] {
        let multideviceSignKeyIds = ownSignKeyIds
        guard !multideviceSignKeyIds.isEmpty else { return [] }

        let messageFilter = NSPredicate.syncableMessagesForAcceptedContacts(
            since: checkpoint,
            ownSignKeyIds: multideviceSignKeyIds
        )
        let messages = try await messageRepositoryFactory
            .createRepository(forFilter: messageFilter)
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let wireMessages = messages.compactMap { Chat.DeviceSyncWireMessage(from: $0) }
        return wireMessages.isEmpty ? [] : [.messages(wireMessages)]
    }

    func transferMessagesPredicate(since checkpoint: UInt64?, upTo bound: UInt64?) -> NSPredicate {
        let predicates = [
            NSPredicate.syncableMessagesForAcceptedContacts(since: checkpoint, ownSignKeyIds: ownSignKeyIds),
            bound.map { NSCompoundPredicate(notPredicateWithSubpredicate: NSPredicate.messagesModifiedAfter($0)) }
        ].compactMap { $0 }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
