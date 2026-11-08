import Foundation
import Operation_iOS
import SubstrateSdk
import Testing

@testable import polkadot_app

@Suite(.timeLimit(.minutes(1)))
struct DeviceUpdateProcessorTests {
    private let facade = UserDataStorageTestFacade()
    private let storage: ObservedContactsStorage
    private let contact: Chat.Contact
    private let device = Chat.PeerDevice(
        statementAccountId: Data(repeating: 0x02, count: 32),
        encryptionPublicKey: Data(repeating: 0x03, count: 32)
    )

    init() async throws {
        storage = ObservedContactsStorage(base: ContactsLocalStorageService(
            storageFacade: facade,
            logger: MockLogger()
        ))
        let contact = Chat.Contact(
            accountId: Data(repeating: 0x01, count: 32),
            username: "Alice",
            publicKey: Data(repeating: 0x05, count: 32),
            pin: nil,
            pushId: nil,
            pushToken: nil,
            voipPushToken: nil,
            peerPlatform: nil,
            lastOwnToken: nil,
            voipLastOwnToken: nil,
            chatRequest: nil,
            ownKeyId: .init(signKeyId: "sign-key", encryptionKeyId: "encryption-key"),
            imageData: nil,
            isBlocked: false,
            devices: [],
            pendingDevicesFanOut: false
        )
        self.contact = contact
        try await facade.makeRepo(mapper: ChatContactMapper()).saveOperation({ [contact] }, { [] }).asyncExecute()
    }

    @Test("A DeviceAdded delivered after a newer DeviceRemoved leaves the device removed")
    func lateOlderAddDoesNotRestoreDevice() async throws {
        let processor = DeviceUpdateProcessor(
            contactsStorageService: storage,
            workQueue: DispatchQueue(label: "DeviceUpdateProcessorTests"),
            logger: MockLogger()
        )

        processor.process(messages: [added(at: 1_000), removed(at: 5_000)], from: contact)
        await storage.waitForDeviceUpdates()
        processor.process(messages: [added(at: 3_000)], from: contact)
        await storage.waitForDeviceUpdates()

        let stored = try await storage.getContact(by: contact.accountId).asyncExecute()
        #expect(stored?.devices == [])
    }
}

private extension DeviceUpdateProcessorTests {
    func added(at timestamp: UInt64) -> Chat.RemoteMessage {
        message(
            .deviceAdded(.init(
                statementAccountId: device.statementAccountId,
                encryptionPublicKey: device.encryptionPublicKey
            )),
            at: timestamp
        )
    }

    func removed(at timestamp: UInt64) -> Chat.RemoteMessage {
        message(.deviceRemoved(.init(statementAccountId: device.statementAccountId)), at: timestamp)
    }

    func message(_ content: Chat.RemoteMessageContentV1.MessageContent, at timestamp: UInt64) -> Chat.RemoteMessage {
        Chat.RemoteMessage(
            messageId: "device-\(timestamp)",
            timestamp: timestamp,
            versioned: .v1(Chat.RemoteMessageContentV1(content: content))
        )
    }
}

/// The real storage, keeping the device updates the processor schedules so a test can wait for them.
private final class ObservedContactsStorage: ContactsLocalStorageServicing, @unchecked Sendable {
    private let base: ContactsLocalStorageServicing
    private let lock = NSLock()
    private var pendingDeviceUpdates: [BaseOperation<Void>] = []

    init(base: ContactsLocalStorageServicing) {
        self.base = base
    }

    func waitForDeviceUpdates() async {
        let operations = lock.withLock {
            defer { pendingDeviceUpdates = [] }
            return pendingDeviceUpdates
        }

        await Task.detached {
            operations.forEach { $0.waitUntilFinished() }
        }.value
    }

    func getContact(by accountId: AccountId) -> BaseOperation<Chat.Contact?> {
        base.getContact(by: accountId)
    }

    func getContact(byPushId pushId: String) -> CompoundOperationWrapper<Chat.Contact?> {
        base.getContact(byPushId: pushId)
    }

    func getEstablishedContacts() -> BaseOperation<[Chat.Contact]> {
        base.getEstablishedContacts()
    }

    func updateOugoingSettings(_ settingsList: [Chat.ContactOutgoingSettings]) -> BaseOperation<Void> {
        base.updateOugoingSettings(settingsList)
    }

    func updateVoIPOugoingSettings(_ settingsList: [Chat.VoIPContactOutgoingSettings]) -> BaseOperation<Void> {
        base.updateVoIPOugoingSettings(settingsList)
    }

    func updateIncomingSettings(_ settingsList: [Chat.ContactIncomingSettings]) -> BaseOperation<Void> {
        base.updateIncomingSettings(settingsList)
    }

    func updateVoIPIncomingSettings(_ settingsList: [Chat.VoIPContactIncomingSettings]) -> BaseOperation<Void> {
        base.updateVoIPIncomingSettings(settingsList)
    }

    func updateDeviceSettings(_ settingsList: [Chat.ContactDeviceSettings]) -> BaseOperation<Void> {
        let operation = base.updateDeviceSettings(settingsList)
        lock.withLock { pendingDeviceUpdates.append(operation) }
        return operation
    }
}
