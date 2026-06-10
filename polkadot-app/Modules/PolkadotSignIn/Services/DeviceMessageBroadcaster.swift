import Foundation
import MessageExchangeKit
import Operation_iOS
import SubstrateSdk

protocol DeviceMessageBroadcasting {
    func broadcastDeviceAdded(
        statementAccountId: Data,
        encryptionPublicKey: Data
    ) async throws

    func broadcastDeviceRemoved(
        statementAccountId: Data
    ) async throws

    func broadcastLocalDevicesOnUpdate(
        oldContact: Chat.Contact?,
        newContact: Chat.Contact
    ) async throws
}

final class DeviceMessageBroadcaster {
    private let contactRepository: AnyDataProviderRepository<Chat.Contact>
    private let messageRepository: AnyDataProviderRepository<Chat.LocalMessage>
    private let localDeviceRepository: AnyDataProviderRepository<Chat.LocalDevice>
    private let messageExchangeModeProvider: MessageExchangeModeProviding
    private let logger: LoggerProtocol

    init(
        contactRepositoryFactory: ChatContactRepositoryMaking = ChatContactRepositoryFactory(),
        messageRepositoryFactory: ChatMessageRepositoryMaking = ChatMessageRepositoryFactory(),
        localDeviceRepositoryFactory: LocalDeviceRepositoryMaking = LocalDeviceRepositoryFactory(),
        messageExchangeModeProvider: MessageExchangeModeProviding,
        logger: LoggerProtocol = Logger.shared
    ) {
        contactRepository = contactRepositoryFactory.createRepository(forFilter: nil)
        messageRepository = messageRepositoryFactory.createRepository(forFilter: nil)
        localDeviceRepository = localDeviceRepositoryFactory.createRepository(forFilter: nil)
        self.messageExchangeModeProvider = messageExchangeModeProvider
        self.logger = logger
    }
}

extension DeviceMessageBroadcaster: DeviceMessageBroadcasting {
    func broadcastDeviceAdded(
        statementAccountId: Data,
        encryptionPublicKey: Data
    ) async throws {
        let content: Chat.LocalMessage.Content = .deviceAdded(.init(
            statementAccountId: statementAccountId,
            encryptionPublicKey: encryptionPublicKey
        ))
        try await broadcastToActiveContacts(content: content, debugLabel: "DeviceAdded")
    }

    func broadcastDeviceRemoved(statementAccountId: Data) async throws {
        let content: Chat.LocalMessage.Content = .deviceRemoved(.init(
            statementAccountId: statementAccountId
        ))
        try await broadcastToActiveContacts(content: content, debugLabel: "DeviceRemoved")
    }

    /// Sends `deviceAdded` for every local device to a contact that just
    /// transitioned from identity-level (0 devices) to device-level.
    func broadcastLocalDevicesOnUpdate(
        oldContact: Chat.Contact?,
        newContact: Chat.Contact
    ) async throws {
        // nil oldContact means .insert, not .update — skip
        guard
            let oldContact,
            messageExchangeModeProvider.mode(for: newContact) == .multidevice,
            oldContact.devices.isEmpty,
            !newContact.devices.isEmpty
        else {
            return
        }

        let localDevices = try await localDeviceRepository
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let messages = localDevices.map { device in
            Chat.LocalMessage.newMessageToPerson(
                newContact.accountId,
                content: .deviceAdded(.init(
                    statementAccountId: device.statementAccountId,
                    encryptionPublicKey: device.encryptionPublicKey
                ))
            )
        }

        try await saveMessages(messages, debugLabel: "DeviceAdded (on update)")
    }
}

private extension DeviceMessageBroadcaster {
    func broadcastToActiveContacts(
        content: Chat.LocalMessage.Content,
        debugLabel: String
    ) async throws {
        let allContacts = try await contactRepository
            .fetchAllOperation(with: .init())
            .asyncExecute()

        let activeContacts = allContacts.filter {
            $0.chatRequest == nil &&
                !$0.isBlocked &&
                messageExchangeModeProvider.mode(for: $0) == .multidevice
        }

        let messages = activeContacts.map {
            Chat.LocalMessage.newMessageToPerson($0.accountId, content: content)
        }

        try await saveMessages(messages, debugLabel: debugLabel)
    }

    func saveMessages(_ messages: [Chat.LocalMessage], debugLabel: String) async throws {
        guard !messages.isEmpty else {
            logger.debug("No messages to broadcast for \(debugLabel)")
            return
        }

        try await messageRepository
            .saveOperation({ messages }, { [] })
            .asyncExecute()

        logger.debug("Broadcast \(messages.count) \(debugLabel) messages")
    }
}
