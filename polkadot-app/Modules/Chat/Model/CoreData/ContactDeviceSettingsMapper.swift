import Foundation
import Operation_iOS
import Foundation_iOS
import CoreData
import SubstrateSdk

extension Chat {
    enum ContactDeviceStatus: Int16 {
        case active = 0
        case inactive = 1
    }

    /// `changedAt` is the peer's event time in milliseconds.
    enum DeviceChange {
        case added(PeerDevice, changedAt: UInt64)
        case removed(statementAccountId: Data, changedAt: UInt64)
    }

    struct ContactDeviceSettings {
        let accountId: AccountId
        let changes: [DeviceChange]
    }
}

final class ContactDeviceSettingsMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Chat.ContactDeviceSettings
    typealias CoreDataEntity = CDChatContact
}

extension ContactDeviceSettingsMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case missingContact
    }

    func transform(entity _: CoreDataEntity) throws -> DataProviderModel {
        throw CoreDataMapperError.unsupported
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using context: NSManagedObjectContext
    ) throws {
        guard entity.identifier != nil else {
            throw MappingError.missingContact
        }

        let existingDevices = entity.devices as? Set<CDContactDevice> ?? []
        var devicesByAccountId = existingDevices.reduce(into: [Data: CDContactDevice]()) { result, device in
            if let statementAccountId = device.statementAccountId {
                result[statementAccountId] = device
            }
        }

        for change in model.changes {
            switch change {
            case let .added(device, changedAt):
                let existing = devicesByAccountId[device.statementAccountId]

                guard existing?.isOlder(than: changedAt) ?? true else {
                    continue
                }

                let deviceEntity = try existing ?? context.insertNew(CDContactDevice.self)
                deviceEntity.statementAccountId = device.statementAccountId
                deviceEntity.encryptionPublicKey = device.encryptionPublicKey
                deviceEntity.contact = entity
                deviceEntity.apply(status: .active, changedAt: changedAt)
                devicesByAccountId[device.statementAccountId] = deviceEntity

            case let .removed(statementAccountId, changedAt):
                guard
                    let existing = devicesByAccountId[statementAccountId],
                    existing.isOlder(than: changedAt)
                else {
                    continue
                }

                existing.apply(status: .inactive, changedAt: changedAt)
            }
        }
    }
}

extension Chat.ContactDeviceSettings: Identifiable {
    var identifier: String {
        accountId.toHex()
    }
}

extension CDContactDevice {
    func isOlder(than changedAt: UInt64) -> Bool {
        self.changedAt < Int64(bitPattern: changedAt)
    }

    func apply(status: Chat.ContactDeviceStatus, changedAt: UInt64) {
        self.status = status.rawValue
        self.changedAt = Int64(bitPattern: changedAt)
        markModified()
        touchParent()
    }

    func markModified() {
        modifiedAt = Date()
    }

    func touchParent() {
        guard let parent = contact else { return }
        let key = #keyPath(CDChatContact.devices)
        parent.willChangeValue(forKey: key)
        parent.didChangeValue(forKey: key)
    }
}
