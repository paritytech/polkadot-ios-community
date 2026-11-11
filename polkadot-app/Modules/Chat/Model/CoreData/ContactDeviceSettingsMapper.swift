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
        /// The device's full state; stores the row if it's unknown, inactive ones included.
        case changed(PeerDevice, status: ContactDeviceStatus, changedAt: UInt64)
        /// Used instead of `changed` when the encryption key isn't known, as for a peer's `DeviceRemoved`:
        /// deactivates a stored row and ignores an unknown one.
        case removed(statementAccountId: Data, changedAt: UInt64)
    }

    struct ContactDeviceSettings {
        let accountId: AccountId
        let changes: [DeviceChange]
        /// False for changes applied from sync, so they aren't sent back.
        var marksModified = true
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

        for change in model.changes {
            let applied = try apply(change, to: entity, using: context)

            if model.marksModified {
                applied?.markModified()
            }
        }
    }
}

private extension ContactDeviceSettingsMapper {
    func apply(
        _ change: Chat.DeviceChange,
        to contact: CDChatContact,
        using context: NSManagedObjectContext
    ) throws -> CDContactDevice? {
        switch change {
        case let .removed(statementAccountId, changedAt):
            guard
                let existing = storedDevice(statementAccountId, of: contact),
                existing.isOlder(than: changedAt)
            else {
                return nil
            }

            existing.apply(status: .inactive, changedAt: changedAt)
            return existing
        case let .changed(device, status, changedAt):
            return try upsert(device, status: status, changedAt: changedAt, of: contact, using: context)
        }
    }

    /// Returns nil when the stored row is as new or newer, so the change is ignored.
    func upsert(
        _ device: Chat.PeerDevice,
        status: Chat.ContactDeviceStatus,
        changedAt: UInt64,
        of contact: CDChatContact,
        using context: NSManagedObjectContext
    ) throws -> CDContactDevice? {
        let existing = storedDevice(device.statementAccountId, of: contact)

        guard existing?.isOlder(than: changedAt) ?? true else {
            return nil
        }

        let deviceEntity = try existing ?? context.insertNew(CDContactDevice.self)
        deviceEntity.statementAccountId = device.statementAccountId
        deviceEntity.encryptionPublicKey = device.encryptionPublicKey
        deviceEntity.contact = contact
        deviceEntity.apply(status: status, changedAt: changedAt)

        return deviceEntity
    }

    func storedDevice(_ statementAccountId: Data, of contact: CDChatContact) -> CDContactDevice? {
        (contact.devices as? Set<CDContactDevice>)?.first { $0.statementAccountId == statementAccountId }
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
