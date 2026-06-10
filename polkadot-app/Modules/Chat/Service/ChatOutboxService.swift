import Foundation
import MessageExchangeKit
import Operation_iOS
import SubstrateSdk
import OperationExt

protocol ChatOutboxServicing: AnyObject {
    var exchangeService: AnyMessageExchangeService<Chat.OpaqueMessage>? { get set }

    func setContactsByAccountId(
        _ contactsByAccountId: [AccountId: Chat.Contact]
    )

    func syncPendingRemoteMessages(
        _ remoteMessages: [Chat.RemoteMessage],
        for peer: MessageExchange.Peer
    )

    func handleSentMessages(
        _ messages: [Chat.RemoteMessage],
        to peer: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    )

    func handleDeliveredMessages(
        _ messages: [Chat.RemoteMessage],
        to peer: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    )

    func sendPeerLeftMessage(to contact: Chat.Contact, completion: @escaping () -> Void)

    // do not trigger APNS push
    func sendDirectly(_ remoteMessage: Chat.RemoteMessage, to peerAccountId: AccountId)
}

final class ChatOutboxService {
    private let logger: LoggerProtocol

    private let messagesStorageService: MessagesLocalStorageServicing
    private let contactsStorageService: ContactsLocalStorageServicing
    private let apnsClientService: APNSClientServicing
    private let notifiedMessageIdRepository: AnyDataProviderRepository<Chat.NotifiedMessageId>

    private let workQueue: DispatchQueue
    private let operationQueue: OperationQueue

    let chatMessageDataProviderFactory: ChatMessageDataProviderMaking
    private var messagesProvider: StreamableProvider<Chat.LocalMessage>?
    private var outboxMessages = OutboxMessageTracker()

    private var sendMessagesDebouncer: Debouncer

    private var isRunning: Bool = false

    var exchangeService: AnyMessageExchangeService<Chat.OpaqueMessage>?

    init(
        messagesStorageService: MessagesLocalStorageServicing,
        contactsStorageService: ContactsLocalStorageServicing,
        apnsClientService: APNSClientServicing,
        notifiedMessageIdRepository: AnyDataProviderRepository<Chat.NotifiedMessageId>,
        chatMessageDataProviderFactory: ChatMessageDataProviderMaking,
        workQueue: DispatchQueue,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.messagesStorageService = messagesStorageService
        self.contactsStorageService = contactsStorageService
        self.apnsClientService = apnsClientService
        self.notifiedMessageIdRepository = notifiedMessageIdRepository
        self.workQueue = workQueue
        self.operationQueue = operationQueue
        self.chatMessageDataProviderFactory = chatMessageDataProviderFactory
        self.logger = logger

        sendMessagesDebouncer = Debouncer(delay: 0.1, queue: workQueue)
    }
}

extension ChatOutboxService: ChatOutboxServicing {
    func setContactsByAccountId(
        _ contactsByAccountId: [AccountId: Chat.Contact]
    ) {
        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            outboxMessages.setContacts(contactsByAccountId)

            if !contactsByAccountId.isEmpty {
                setup()

                schedulePendingMessagesIfNeeded()
            } else {
                suspend()
            }
        }
    }

    func syncPendingRemoteMessages(
        _ messages: [Chat.RemoteMessage],
        for peer: MessageExchange.Peer
    ) {
        workQueue.async { [weak self] in
            self?.handleSyncPendingRemoteMessages(messages, contactId: peer.accountId)
        }
    }

    func handleSentMessages(
        _ messages: [Chat.RemoteMessage],
        to peer: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            markSentMessages(
                messages,
                to: peer,
                withError: error
            )
        }
    }

    func handleDeliveredMessages(
        _ messages: [Chat.RemoteMessage],
        to peer: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            markDeliveredMessages(
                messages,
                to: peer,
                withError: error
            )
        }
    }

    func sendPeerLeftMessage(to contact: Chat.Contact, completion: @escaping () -> Void) {
        workQueue.async { [weak self] in
            guard let self else {
                completion()
                return
            }

            guard let exchangeService else {
                completion()
                return
            }

            let message = Chat.RemoteMessage.newMessage(with: .leftChat)

            let peer = contact.toMessageExchangePeer()

            exchangeService.addMessageToQueue(.init(remoteMessage: message), for: peer)
            notifyAboutNewMessages([message], contact: contact)
            completion()
        }
    }

    func sendDirectly(_ remoteMessage: Chat.RemoteMessage, to peerAccountId: AccountId) {
        workQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard let exchangeService else {
                logger.warning("Cannot send directly: missing exchange service")
                return
            }

            guard let contact = outboxMessages.getContact(for: peerAccountId) else {
                logger.warning("Cannot send directly: missing contact for \(peerAccountId.toHex())")
                return
            }

            let peer = contact.toMessageExchangePeer()
            exchangeService.addMessageToQueue(.init(remoteMessage: remoteMessage), for: peer)
        }
    }
}

// MARK: - Sending Messages handling

private extension ChatOutboxService {
    private func setup() {
        guard !isRunning else {
            return
        }

        subscribeToNewMessages()
        isRunning = true
    }

    private func suspend() {
        guard isRunning else {
            return
        }

        clear(streamableProvider: &messagesProvider)
        sendMessagesDebouncer.cancel()
        outboxMessages.clear()
        isRunning = false
    }

    func schedulePendingMessagesIfNeeded() {
        if outboxMessages.hasMessagesToSend {
            logger.debug("Schedule message send")
            sendMessagesDebouncer.debounce { [weak self] in
                self?.sendAllPendingMessages()
            }
        }
    }

    func sendAllPendingMessages() {
        guard let exchangeService else {
            logger.error("Missing exchange service")
            assertionFailure()
            return
        }

        let outboxes = outboxMessages.prepareMessagesToSend()

        for outbox in outboxes {
            let peer = outbox.contact.toMessageExchangePeer()

            outboxMessages.markInFlight(messageIds: outbox.messageIds())

            logger.debug("Sending messages: \(outbox.messagesToSend.count)")

            for message in outbox.messagesToSend {
                // TODO: Allow multiple messages at once
                if let remote = message.toRemote() {
                    exchangeService.addMessageToQueue(
                        Chat.OpaqueMessage(remoteMessage: remote),
                        for: peer
                    )
                }
            }
        }
    }

    func markSentMessages(
        _ messages: [Chat.RemoteMessage],
        to peer: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        let messageIds = messages.map(\.messageId)
        let onlyNew = outboxMessages.markSent(messageIds: Set(messageIds))

        if let error {
            logger.error("Failed to send message: \(error)")
            return
        }

        guard let contact = outboxMessages.getContact(for: peer.accountId) else {
            logger.warning("Missing contact to mark message sent")
            return
        }

        let messagesToNotify = messages.filter { onlyNew.contains($0.messageId) }

        notifyAboutNewMessages(messagesToNotify, contact: contact)

        let localMessageIds = messages
            .filter { onlyNew.contains($0.messageId) && Chat.LocalMessage.supportsRemote($0) }
            .map(\.messageId)

        guard !localMessageIds.isEmpty else {
            return
        }

        let statusWrapper = messagesStorageService.markAsSent(localMessageIds)

        execute(
            wrapper: statusWrapper,
            inOperationQueue: operationQueue,
            runningCallbackIn: workQueue
        ) { [logger] result in
            switch result {
            case .success:
                logger.info("Messages status update to .sent")
            case let .failure(error):
                logger.error("Failed to update message status to .sent \(error)")
            }
        }
    }

    func markDeliveredMessages(
        _ messages: [Chat.RemoteMessage],
        to _: MessageExchange.Peer,
        withError error: MessageExchange.OutgoingMessageError?
    ) {
        if let error {
            logger.error("Messages delivery failed: \(error)")
            return
        }

        let messageIds = messages.map(\.messageId)

        removeNotifiedMessageIds(messageIds)

        let localMessageIds = messages.compactMap { message in
            Chat.LocalMessage.supportsRemote(message) ? message.messageId : nil
        }

        guard !localMessageIds.isEmpty else {
            return
        }

        let statusWrapper = messagesStorageService.markAsDelivered(localMessageIds)

        execute(
            wrapper: statusWrapper,
            inOperationQueue: operationQueue,
            runningCallbackIn: workQueue
        ) { [logger] result in
            switch result {
            case .success:
                logger.info("Messages delivery saved successfully")
            case let .failure(error):
                logger.debug("Failed to save delivered messages messageId. Error: \(error)")
            }
        }
    }

    func handleSyncPendingRemoteMessages(_ messages: [Chat.RemoteMessage], contactId: AccountId) {
        guard !messages.isEmpty else {
            logger.debug("No pending messages to sync")
            return
        }

        let messageIds = Set(messages.map(\.messageId))

        let syncWrapper = messagesStorageService.markSentAsNewIfMissingIn(
            messageIds: messageIds,
            contactId: contactId
        )

        execute(
            wrapper: syncWrapper,
            inOperationQueue: operationQueue,
            runningCallbackIn: workQueue
        ) { [logger] result in
            switch result {
            case .success:
                logger.info("Synced pending remote messages")
            case let .failure(error):
                logger.error("Failed to sync pending remote messages: \(error)")
            }
        }
    }

    func notifyAboutNewMessages(
        _ messages: [Chat.RemoteMessage],
        contact: Chat.Contact
    ) {
        guard !messages.isEmpty else { return }

        let fetchOperation = notifiedMessageIdRepository.fetchAllOperation(
            with: RepositoryFetchOptions()
        )

        let filterOperation = ClosureOperation<[Chat.RemoteMessage]> {
            let notifiedMessageIds = try fetchOperation.extractNoCancellableResultData()
            let notifiedSet = Set(notifiedMessageIds.map(\.messageId))

            return messages.filter {
                !notifiedSet.contains($0.messageId) && $0.supportsNotification()
            }
        }

        let notifyOperation: BaseOperation<[String]> = OperationCombiningService(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else { return [] }

            let messagesToNotify = try filterOperation.extractNoCancellableResultData()

            return messagesToNotify.map { message in
                let wrapper = self.apnsClientService.notifyAboutNewMessageWrapper(
                    message,
                    contact: contact
                )

                let mapOperation = ClosureOperation<String> {
                    let response = try wrapper.targetOperation.extractNoCancellableResultData()
                    self.logger.debug("Response: \(response)")
                    return message.messageId
                }
                mapOperation.addDependency(wrapper.targetOperation)

                return CompoundOperationWrapper(
                    targetOperation: mapOperation,
                    dependencies: wrapper.allOperations
                )
            }
        }.longrunOperation()

        let saveOperation = notifiedMessageIdRepository.saveOperation(
            { try notifyOperation.extractNoCancellableResultData().map { .init(messageId: $0) } },
            { [] }
        )

        filterOperation.addDependency(fetchOperation)
        notifyOperation.addDependency(filterOperation)
        saveOperation.addDependency(notifyOperation)

        let wrapper = CompoundOperationWrapper(
            targetOperation: saveOperation,
            dependencies: [fetchOperation, filterOperation, notifyOperation]
        )

        execute(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            runningCallbackIn: workQueue
        ) { [logger] result in
            switch result {
            case .success:
                logger.debug("Notifications sent successfully")
            case let .failure(error):
                logger.error("Failed to notify about new messages: \(error)")
            }
        }
    }

    func removeNotifiedMessageIds(_ messageIds: [String]) {
        let deleteOperation = notifiedMessageIdRepository.saveOperation(
            { [] },
            { messageIds }
        )

        execute(
            wrapper: CompoundOperationWrapper(targetOperation: deleteOperation),
            inOperationQueue: operationQueue,
            runningCallbackIn: workQueue
        ) { [logger] result in
            switch result {
            case .success:
                logger.debug("Removed \(messageIds.count) notified message IDs")
            case let .failure(error):
                logger.error("Failed to remove notified message IDs: \(error)")
            }
        }
    }
}

extension ChatOutboxService: ChatMessageDataSubscribing, ChatMessageDataHandling, AnyProviderAutoCleaning {
    func subscribeToNewMessages() {
        clear(streamableProvider: &messagesProvider)
        messagesProvider = subscribeOnNewMessagesLifecycle(on: workQueue)
    }

    func handleChatMessages(result: Result<[DataProviderChange<Chat.LocalMessage>], Error>) {
        switch result {
        case let .success(changes):
            apply(changes: changes)

            schedulePendingMessagesIfNeeded()
        case let .failure(error):
            logger.error("chat provider error: \(error)")
        }
    }
}

// MARK: - New messages handling

private extension ChatOutboxService {
    func apply(changes: [DataProviderChange<Chat.LocalMessage>]) {
        changes.forEach { change in
            switch change {
            case let .insert(newMessage):
                logger.debug("New message: \(newMessage.messageId)")
                guard
                    newMessage.creationSource == .localDevice,
                    newMessage.status == .outgoing(.new),
                    newMessage.canSendToRemote()
                else {
                    logger.debug("Message is not ready. Skipped")
                    return
                }

                outboxMessages.insert(messages: [newMessage])

            case let .update(updatedMessage):
                logger.debug("Updated message: \(updatedMessage.messageId)")
                guard updatedMessage.status.isOutgoing else {
                    return
                }

                if updatedMessage.creationSource == .localDevice,
                   updatedMessage.status == .outgoing(.new),
                   updatedMessage.canSendToRemote() {
                    outboxMessages.insert(messages: [updatedMessage])
                } else {
                    logger.debug("Message is not new or not ready: \(updatedMessage.messageId). Removing if pending")
                    // Message left .new state or can't be sent
                    // remove from snapshot and clear inFlight
                    outboxMessages.remove(messageIds: [updatedMessage.messageId])
                }

            case let .delete(deletedMessageId):
                logger.debug("Message removed: \(deletedMessageId)")
                outboxMessages.remove(messageIds: [deletedMessageId])
            }
        }
    }
}
