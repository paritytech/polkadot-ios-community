import Foundation
import Operation_iOS

struct DeviceSyncIncomingUpdateApplier {
    private let remoteContactResolver: RemoteContactResolving
    private let contactRepositoryFactory: ChatContactRepositoryMaking
    private let chatRepositoryFactory: ChatRepositoryMaking
    private let messageRepositoryFactory: ChatMessageRepositoryMaking
    private let removedChatRepositoryFactory: RemovedChatRepositoryMaking
    private let chatAcceptedApplier: DeviceSyncChatAcceptedApplier
    private let deviceChangesApplier: DeviceSyncDeviceChangesApplier
    private let logger: LoggerProtocol

    init(
        remoteContactResolver: RemoteContactResolving,
        contactRepositoryFactory: ChatContactRepositoryMaking,
        chatRepositoryFactory: ChatRepositoryMaking,
        messageRepositoryFactory: ChatMessageRepositoryMaking,
        removedChatRepositoryFactory: RemovedChatRepositoryMaking,
        contactsStorageService: ContactsLocalStorageServicing = ContactsLocalStorageService(),
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        logger: LoggerProtocol
    ) {
        self.remoteContactResolver = remoteContactResolver
        self.contactRepositoryFactory = contactRepositoryFactory
        self.chatRepositoryFactory = chatRepositoryFactory
        self.messageRepositoryFactory = messageRepositoryFactory
        self.removedChatRepositoryFactory = removedChatRepositoryFactory
        chatAcceptedApplier = DeviceSyncChatAcceptedApplier(
            storageFacade: storageFacade,
            contactsStorageService: contactsStorageService,
            messageExchangeModeProvider: ChatMessageExchangeModeProvider(),
            logger: logger
        )
        deviceChangesApplier = DeviceSyncDeviceChangesApplier(
            contactsStorageService: contactsStorageService,
            logger: logger
        )
        self.logger = logger
    }

    func applyEntity(
        _ entity: Chat.DeviceSyncEntity,
        updateTimePoint: UInt64
    ) async throws {
        switch entity {
        case let .devices(devices):
            logger.debug("Applying \(devices.count) device(s) from sync (no-op, handled by SSO)")
        case let .chatsAdded(chatIds):
            logger.debug("Applying \(chatIds.count) chatsAdded from sync")
            try await applyChatsAdded(chatIds, updateTimePoint: updateTimePoint)
        case let .chatsRemoved(chatIds):
            logger.debug("Applying \(chatIds.count) chatsRemoved from sync")
            try await applyChatsRemoved(chatIds, remoteTimestamp: updateTimePoint)
        case let .messages(messages):
            logger.debug("Applying \(messages.count) message(s) from sync")
            try await applyMessages(messages)
        }
    }
}

private extension DeviceSyncIncomingUpdateApplier {
    func applyChatsAdded(
        _ chatIds: [Chat.DeviceSyncChatId],
        updateTimePoint: UInt64
    ) async throws {
        let contactRepository = contactRepositoryFactory.createRepository(forFilter: nil)
        let chatRepository = chatRepositoryFactory.createRepository(forFilter: nil)

        for chatId in chatIds {
            switch chatId {
            case let .contact(accountId):
                let hex = accountId.toHex()

                let existing = try await contactRepository
                    .fetchOperation(by: { hex }, options: .init())
                    .asyncExecute()

                guard existing == nil else {
                    logger.debug("Contact \(hex) already exists, skipping")
                    continue
                }

                guard let remoteContact = try await remoteContactResolver.fetch(
                    by: accountId
                ) else {
                    logger.warning("No on-chain data for synced contact \(hex), skipping")
                    continue
                }

                var contact = Chat.Contact(
                    remoteContact: remoteContact,
                    ownKeyId: .main()
                )
                contact.acceptedAt = Date.fromChatTimestamp(updateTimePoint)

                let saveContactOp = contactRepository.saveOperation({ [contact] }, { [] })
                try await saveContactOp.asyncExecute()

                let chat = Chat.LocalModel.newChatWithContact(contact)
                let saveChatOp = chatRepository.saveOperation({ [chat] }, { [] })
                try await saveChatOp.asyncExecute()

                logger.debug("Resolved and saved synced contact \(hex) with chat")
            }
        }
    }

    func applyChatsRemoved(
        _ chatIds: [Chat.DeviceSyncChatId],
        remoteTimestamp: UInt64
    ) async throws {
        let identifiersToRemove = chatIds.map { chatId in
            switch chatId {
            case let .contact(accountId):
                accountId.toHex()
            }
        }

        guard !identifiersToRemove.isEmpty else { return }

        let contactRepository = contactRepositoryFactory.createRepository(forFilter: nil)
        let deleteOperation = contactRepository.saveOperation({ [] }, { identifiersToRemove })
        try await deleteOperation.asyncExecute()

        // Record tombstones so the removal is synced to other devices as well.
        // Use the remote peer's timestamp for correct dedup across devices.
        let removedChatRepository = removedChatRepositoryFactory.createRepository(forFilter: nil)
        let removedAt = Date.fromChatTimestamp(remoteTimestamp)
        let tombstones = chatIds.map { chatId -> Chat.RemovedChat in
            switch chatId {
            case let .contact(accountId):
                Chat.RemovedChat(accountId: accountId, removedAt: removedAt)
            }
        }
        let tombstoneOperation = removedChatRepository.saveOperation({ tombstones }, { [] })
        try await tombstoneOperation.asyncExecute()

        logger.debug("Removed \(identifiersToRemove.count) contact(s) from sync")
    }

    func applyMessages(_ wireMessages: [Chat.DeviceSyncWireMessage]) async throws {
        try await chatAcceptedApplier.apply(wireMessages)

        let localMessages = wireMessages.compactMap { $0.toLocal() }
        logger.debug("Applying \(localMessages.count) from \(wireMessages.count) message(s) from sync")

        guard !localMessages.isEmpty else {
            logger.debug("No local messages to apply after conversion")
            return
        }

        let messageRepository = messageRepositoryFactory.createRepository(forFilter: nil)
        let incomingMessageFilter = DeviceSyncIncomingMessageFilter(
            repository: messageRepository,
            logger: logger
        )
        let messagesToSave = try await incomingMessageFilter.filterMessagesToApply(
            in: localMessages
        )
        let operation = messageRepository.saveOperation({ messagesToSave }, { [] })
        try await operation.asyncExecute()

        try await deviceChangesApplier.apply(wireMessages)

        logger.debug("Applied \(messagesToSave.count) of \(localMessages.count) message(s) from sync")
    }
}
