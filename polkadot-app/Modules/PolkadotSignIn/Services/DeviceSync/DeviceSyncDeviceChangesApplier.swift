import Foundation
import Operation_iOS

struct DeviceSyncDeviceChangesApplier {
    private let contactsStorageService: ContactsLocalStorageServicing
    private let logger: LoggerProtocol

    init(
        contactsStorageService: ContactsLocalStorageServicing = ContactsLocalStorageService(),
        logger: LoggerProtocol
    ) {
        self.contactsStorageService = contactsStorageService
        self.logger = logger
    }

    func apply(_ wireMessages: [Chat.DeviceSyncWireMessage]) async throws {
        var changesByContact: [Data: [Chat.DeviceChange]] = [:]
        let sortedMessages = wireMessages.sorted { $0.remote.timestamp < $1.remote.timestamp }

        for wireMessage in sortedMessages {
            guard case .incoming = wireMessage.status else {
                continue
            }

            guard let change = deviceChange(from: wireMessage.remote) else {
                continue
            }

            changesByContact[wireMessage.peerId, default: []].append(change)
        }

        try await apply(changesByContact)
    }
}

private extension DeviceSyncDeviceChangesApplier {
    func apply(_ changesByContact: [Data: [Chat.DeviceChange]]) async throws {
        let settings = changesByContact.map { accountId, changes in
            Chat.ContactDeviceSettings(accountId: accountId, changes: changes)
        }

        guard !settings.isEmpty else {
            return
        }

        try await contactsStorageService.updateDeviceSettings(settings).asyncExecute()
        logger.debug("Applied device changes from sync for \(settings.count) contact(s)")
    }

    func deviceChange(from message: Chat.RemoteMessage) -> Chat.DeviceChange? {
        guard let content = message.versioned.ensureV1()?.content else {
            return nil
        }

        switch content {
        case let .deviceAdded(content):
            let device = Chat.PeerDevice(
                statementAccountId: content.statementAccountId,
                encryptionPublicKey: content.encryptionPublicKey
            )
            return .added(device)
        case let .deviceRemoved(content):
            return .removed(statementAccountId: content.statementAccountId)
        default:
            return nil
        }
    }
}
