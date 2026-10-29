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

/// Position in the sync order `(order, timestamp, messageId)`: the order the old phone stored messages in, with
/// `timestamp` ordering legacy rows that all have order 0.
struct DeviceTransferMessageCursor: Equatable {
    let order: UInt64
    let timestamp: UInt64
    let messageId: String
}

struct DeviceTransferMessagePage {
    var messages: [Chat.DeviceSyncWireMessage]
    var nextCursor: DeviceTransferMessageCursor?
}

protocol DeviceTransferChangesCollecting {
    func collectChatStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity]
    func collectCoinageStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity]

    /// `modifiedUpTo` is compared with `modifiedAt`, or with `timestamp` for legacy rows that have none.
    func collectMessagePage(
        since checkpoint: UInt64?,
        modifiedUpTo bound: UInt64?,
        after cursor: DeviceTransferMessageCursor?,
        limit: Int
    ) async throws -> DeviceTransferMessagePage

    func countMessages(since checkpoint: UInt64?, modifiedUpTo bound: UInt64?) async throws -> Int
}

extension DeviceSyncOutgoingChangesCollector: DeviceTransferChangesCollecting {
    func collectChatStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity] {
        let cutoff = checkpoint.map { Date.fromChatTimestamp($0) }

        return try await collectContactChanges(after: cutoff)
            + collectRemovedChatChanges(after: cutoff)
            + chatStateCollector.collect(after: cutoff)
    }

    func collectCoinageStateEntities(since checkpoint: UInt64?) async throws -> [Chat.DeviceSyncEntity] {
        try await coinageStateCollector.collect(after: checkpoint.map { Date.fromChatTimestamp($0) })
    }

    func collectMessagePage(
        since checkpoint: UInt64?,
        modifiedUpTo bound: UInt64?,
        after cursor: DeviceTransferMessageCursor?,
        limit: Int
    ) async throws -> DeviceTransferMessagePage {
        let predicates = [
            transferMessagesPredicate(since: checkpoint, modifiedUpTo: bound),
            cursor.map { NSPredicate.messagesInSyncOrder(after: $0) }
        ].compactMap { $0 }

        let messages = try await messageRepositoryFactory
            .createRepository(
                forFilter: NSCompoundPredicate(andPredicateWithSubpredicates: predicates),
                sortDescriptors: NSSortDescriptor.messagesInSyncOrder
            )
            .fetchOperation(by: RepositorySliceRequest(offset: 0, count: limit, reversed: false), options: .init())
            .asyncExecute()

        return DeviceTransferMessagePage(
            messages: messages.compactMap { Chat.DeviceSyncWireMessage(from: $0) },
            nextCursor: messages.count < limit ? nil : messages.last.map(DeviceTransferMessageCursor.init)
        )
    }

    func countMessages(since checkpoint: UInt64?, modifiedUpTo bound: UInt64?) async throws -> Int {
        try await messageRepositoryFactory
            .createRepository(forFilter: transferMessagesPredicate(since: checkpoint, modifiedUpTo: bound))
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
            .createRepository(forFilter: messageFilter, sortDescriptors: NSSortDescriptor.messagesInSyncOrder)
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let wireMessages = messages.compactMap { Chat.DeviceSyncWireMessage(from: $0) }
        return wireMessages.isEmpty ? [] : [.messages(wireMessages)]
    }

    func transferMessagesPredicate(since checkpoint: UInt64?, modifiedUpTo bound: UInt64?) -> NSPredicate {
        let predicates = [
            NSPredicate.syncableMessagesForAcceptedContacts(since: checkpoint, ownSignKeyIds: ownSignKeyIds),
            bound.map { NSCompoundPredicate(notPredicateWithSubpredicate: NSPredicate.messagesModifiedAfter($0)) }
        ].compactMap { $0 }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

private extension DeviceTransferMessageCursor {
    init(_ message: Chat.LocalMessage) {
        self.init(order: message.order, timestamp: message.timestamp, messageId: message.messageId)
    }
}

private extension NSPredicate {
    static func messagesInSyncOrder(after cursor: DeviceTransferMessageCursor) -> NSPredicate {
        let order = #keyPath(CDChatMessage.order)
        let timestamp = #keyPath(CDChatMessage.timestamp)
        let rawOrder = Int64(bitPattern: cursor.order)
        let rawTimestamp = Int64(bitPattern: cursor.timestamp)

        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K > %lld", order, rawOrder),
            NSPredicate(format: "%K == %lld AND %K > %lld", order, rawOrder, timestamp, rawTimestamp),
            NSPredicate(
                format: "%K == %lld AND %K == %lld AND %K > %@",
                order,
                rawOrder,
                timestamp,
                rawTimestamp,
                #keyPath(CDChatMessage.messageId),
                cursor.messageId
            )
        ])
    }
}

private extension NSSortDescriptor {
    static var messagesInSyncOrder: [NSSortDescriptor] {
        [
            NSSortDescriptor(key: #keyPath(CDChatMessage.order), ascending: true),
            NSSortDescriptor(key: #keyPath(CDChatMessage.timestamp), ascending: true),
            NSSortDescriptor(key: #keyPath(CDChatMessage.messageId), ascending: true)
        ]
    }
}
