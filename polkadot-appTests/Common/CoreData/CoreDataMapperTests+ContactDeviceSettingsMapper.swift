import CoreData
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("ContactDeviceSettingsMapper")
    struct ContactDeviceSettingsMapperTests {
        private let facade = UserDataStorageTestFacade()
        private let contactAccountId = Data(repeating: 0x01, count: 32)

        @Test("a newer add of the same device keeps one row with the newer key")
        func newerAddUpdatesKey() async throws {
            try await seedContact(devices: [])

            let device = makeDevice(accountByte: 0x02, keyByte: 0x03)
            let updatedDevice = makeDevice(accountByte: 0x02, keyByte: 0x04)

            try await updateDevices([
                .added(device, changedAt: 1),
                .added(updatedDevice, changedAt: 2)
            ])

            let rows = try await fetchDeviceRows()
            #expect(rows.count == 1)
            #expect(rows.first?.encryptionPublicKey == updatedDevice.encryptionPublicKey)
            #expect(rows.first?.status == .active)
            #expect(rows.first?.changedAt == 2)
            #expect(rows.first?.modifiedAt != nil)
        }

        @Test("a removal keeps the device as an inactive row")
        func removalKeepsInactiveRow() async throws {
            try await seedContact(devices: [])

            let device = makeDevice(accountByte: 0x02, keyByte: 0x03)

            try await updateDevices([
                .added(device, changedAt: 1),
                .removed(statementAccountId: device.statementAccountId, changedAt: 2)
            ])

            let rows = try await fetchDeviceRows()
            #expect(rows.count == 1)
            #expect(rows.first?.status == .inactive)
            #expect(rows.first?.changedAt == 2)
        }

        @Test("a change older than the stored one is ignored")
        func olderChangeIsIgnored() async throws {
            try await seedContact(devices: [])

            let device = makeDevice(accountByte: 0x02, keyByte: 0x03)
            try await updateDevices([
                .added(device, changedAt: 1),
                .removed(statementAccountId: device.statementAccountId, changedAt: 5)
            ])
            try await updateDevices([.added(device, changedAt: 3)])

            let rows = try await fetchDeviceRows()
            #expect(rows.count == 1)
            #expect(rows.first?.status == .inactive)
            #expect(rows.first?.changedAt == 5)
        }

        @Test("a newer add reactivates a removed device with its new key")
        func newerAddReactivatesRemovedDevice() async throws {
            let oldDevice = makeDevice(accountByte: 0x02, keyByte: 0x03)
            let newDevice = makeDevice(accountByte: 0x02, keyByte: 0x04)
            try await seedContact(devices: [oldDevice])

            try await updateDevices([
                .removed(statementAccountId: oldDevice.statementAccountId, changedAt: 1),
                .added(newDevice, changedAt: 2)
            ])

            let rows = try await fetchDeviceRows()
            #expect(rows.count == 1)
            #expect(rows.first?.encryptionPublicKey == newDevice.encryptionPublicKey)
            #expect(rows.first?.status == .active)
        }

        @Test("saving the contact again keeps a removed device inactive")
        func contactSaveKeepsInactiveDevice() async throws {
            let device = makeDevice(accountByte: 0x02, keyByte: 0x03)
            try await seedContact(devices: [device])
            try await updateDevices([.removed(statementAccountId: device.statementAccountId, changedAt: 1)])

            let contact = try #require(
                try await contactRepository
                    .fetchOperation(by: { contactAccountId.toHex() }, options: .init())
                    .asyncExecute()
            )
            try await contactRepository.saveOperation({ [contact] }, { [] }).asyncExecute()

            let rows = try await fetchDeviceRows()
            #expect(rows.count == 1)
            #expect(rows.first?.status == .inactive)
            #expect(rows.first?.changedAt == 1)
        }
    }
}

private extension CoreDataMapperTests.ContactDeviceSettingsMapperTests {
    var contactRepository: AnyDataProviderRepository<Chat.Contact> {
        facade.makeRepo(mapper: ChatContactMapper())
    }

    var deviceSettingsRepository: AnyDataProviderRepository<Chat.ContactDeviceSettings> {
        facade.makeRepo(mapper: ContactDeviceSettingsMapper())
    }

    func seedContact(devices: [Chat.PeerDevice]) async throws {
        let contact = Chat.Contact(
            accountId: contactAccountId,
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
            devices: devices,
            pendingDevicesFanOut: false
        )

        try await contactRepository.saveOperation({ [contact] }, { [] }).asyncExecute()
    }

    func updateDevices(_ changes: [Chat.DeviceChange]) async throws {
        let settings = Chat.ContactDeviceSettings(
            accountId: contactAccountId,
            changes: changes
        )

        try await deviceSettingsRepository.saveOperation({ [settings] }, { [] }).asyncExecute()
    }

    struct DeviceRow {
        let encryptionPublicKey: Data?
        let status: Chat.ContactDeviceStatus?
        let changedAt: Int64
        let modifiedAt: Date?
    }

    func fetchDeviceRows() async throws -> [DeviceRow] {
        try await withCheckedThrowingContinuation { continuation in
            facade.databaseService.performAsync { context, error in
                guard let context else {
                    continuation.resume(throwing: error ?? CoreDataRepositoryError.undefined)
                    return
                }

                context.performAndWait {
                    continuation.resume(with: Result {
                        try context.fetch(CDContactDevice.fetchRequest()).map {
                            DeviceRow(
                                encryptionPublicKey: $0.encryptionPublicKey,
                                status: Chat.ContactDeviceStatus(rawValue: $0.status),
                                changedAt: $0.changedAt,
                                modifiedAt: $0.modifiedAt
                            )
                        }
                    })
                }
            }
        }
    }

    func makeDevice(accountByte: UInt8, keyByte: UInt8) -> Chat.PeerDevice {
        Chat.PeerDevice(
            statementAccountId: Data(repeating: accountByte, count: 32),
            encryptionPublicKey: Data(repeating: keyByte, count: 32)
        )
    }
}
