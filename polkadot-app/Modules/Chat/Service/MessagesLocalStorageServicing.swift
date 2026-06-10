import Foundation
import Operation_iOS
import CoreData
import SubstrateSdk

protocol MessagesLocalStorageServicing {
    func message(
        with messageIdClosure: @escaping () throws -> String
    ) -> BaseOperation<Chat.LocalMessage?>

    func insertOrUpdate(
        _ messagesClosure: @escaping () throws -> [Chat.LocalMessage]
    ) -> BaseOperation<Void>

    func insertOrUpdate(_ messages: [Chat.LocalMessage]) -> BaseOperation<Void>

    func markAsSent(_ messageIds: [String]) -> CompoundOperationWrapper<Void>
    func markAsDelivered(_ messageIds: [String]) -> CompoundOperationWrapper<Void>
    func markAsSeen(_ messageIds: [String]) -> CompoundOperationWrapper<Void>

    func markSentAsNewIfMissingIn(
        messageIds: Set<String>,
        contactId: AccountId
    ) -> CompoundOperationWrapper<Void>
}

final class MessagesLocalStorageService: MessagesLocalStorageServicing {
    private let repositoryFactory: ChatMessageRepositoryMaking
    private let statusUpdateRepositoryFactory: ChatMessageStatusUpdateRepositoryMaking
    private let logger: LoggerProtocol

    init(
        repositoryFactory: ChatMessageRepositoryMaking = ChatMessageRepositoryFactory(),
        statusUpdateRepositoryFactory: ChatMessageStatusUpdateRepositoryMaking =
            ChatMessageStatusUpdateRepositoryFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.repositoryFactory = repositoryFactory
        self.statusUpdateRepositoryFactory = statusUpdateRepositoryFactory
        self.logger = logger
    }

    func message(
        with messageIdClosure: @escaping () throws -> String
    ) -> BaseOperation<Chat.LocalMessage?> {
        let repository = repositoryFactory.createRepository(forFilter: nil)
        return repository.fetchOperation(by: messageIdClosure, options: .init())
    }

    func insertOrUpdate(
        _ messagesClosure: @escaping () throws -> [Chat.LocalMessage]
    ) -> BaseOperation<Void> {
        let repository = repositoryFactory.createRepository(forFilter: nil)
        return repository.saveOperation(messagesClosure) { [] }
    }

    func insertOrUpdate(_ messages: [Chat.LocalMessage]) -> BaseOperation<Void> {
        let repository = repositoryFactory.createRepository(forFilter: nil)
        return repository.saveOperation({ messages }, { [] })
    }

    func markAsSent(_ messageIds: [String]) -> CompoundOperationWrapper<Void> {
        updateStatusWrapper(for: messageIds, to: .outgoing(.sent))
    }

    func markAsDelivered(_ messageIds: [String]) -> CompoundOperationWrapper<Void> {
        updateStatusWrapper(for: messageIds, to: .outgoing(.delivered))
    }

    func markAsSeen(_ messageIds: [String]) -> CompoundOperationWrapper<Void> {
        updateStatusWrapper(for: messageIds, to: .incoming(.seen))
    }

    func markSentAsNewIfMissingIn(
        messageIds: Set<String>,
        contactId: AccountId
    ) -> CompoundOperationWrapper<Void> {
        let filter = NSPredicate.sentLocalDeviceMessages(to: .person(contactId))

        let repository = statusUpdateRepositoryFactory.createRepository(forFilter: filter)

        let fetchAll = repository.fetchAllOperation(with: .init())

        let filteredUpdates = ClosureOperation<[Chat.ChatMessageStatusUpdate]> {
            let messagesToUpdate = try fetchAll.extractNoCancellableResultData()

            return messagesToUpdate.compactMap { messageToUpdate in
                guard !messageIds.contains(messageToUpdate.messageId) else {
                    return nil
                }

                return messageToUpdate.replacingStatus(.outgoing(.new))
            }
        }

        filteredUpdates.addDependency(fetchAll)

        let saveOperation = repository.saveOperation({
            try filteredUpdates.extractNoCancellableResultData()
        }, {
            []
        })

        saveOperation.addDependency(filteredUpdates)

        return CompoundOperationWrapper(
            targetOperation: saveOperation,
            dependencies: [fetchAll, filteredUpdates]
        )
    }
}

// MARK: - Helpers

private extension MessagesLocalStorageService {
    func updateStatusWrapper(
        for messageIds: [String],
        to newStatus: Chat.LocalMessage.Status
    ) -> CompoundOperationWrapper<Void> {
        guard !messageIds.isEmpty else {
            return .createWithResult(())
        }

        let repository = statusUpdateRepositoryFactory.createRepository(
            forFilter: .messages(withIds: messageIds)
        )

        let fetchExisting = repository.fetchAllOperation(with: .init())

        let saveOperation = repository.saveOperation({
            try fetchExisting.extractNoCancellableResultData().map {
                $0.replacingStatus(newStatus)
            }
        }, { [] })

        saveOperation.addDependency(fetchExisting)

        return CompoundOperationWrapper(
            targetOperation: saveOperation,
            dependencies: [fetchExisting]
        )
    }
}
