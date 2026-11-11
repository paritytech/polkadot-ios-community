import Foundation
import Operation_iOS
import Foundation_iOS
import CoreData
import SubstrateSdk
import SubstrateSdkExt

final class ChatContactMapper {
    var entityIdentifierFieldName: String {
        #keyPath(CoreDataEntity.identifier)
    }

    typealias DataProviderModel = Chat.Contact
    typealias CoreDataEntity = CDChatContact
}

extension ChatContactMapper: CoreDataMapperProtocol {
    enum MappingError: Error {
        case missingChatRequestEntity
    }

    func transform(entity: CoreDataEntity) throws -> DataProviderModel {
        guard let accountId = try entity.identifier?.fromHex() else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.identifier)
            )
        }

        guard let publicKey = entity.publicKey else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.publicKey)
            )
        }

        guard let username = entity.username else {
            throw CoreDataMapperError.missingRequiredData(
                keyPath: #keyPath(CoreDataEntity.username)
            )
        }

        let peerPlatform = entity.pushPlatform.flatMap {
            Chat.PeerPlatform(rawValue: $0)
        }

        let chatRequest = try entity.chatRequest.map { requestEntity in
            try ChatRequestMapper().transform(entity: requestEntity)
        }

        let ownKeyId = try Chat.Contact.Own(entity: entity)

        let devices = (entity.devices as? Set<CDContactDevice>)?.compactMap { deviceEntity -> Chat.PeerDevice? in
            guard deviceEntity.status == Chat.ContactDeviceStatus.active.rawValue,
                  let statementAccountId = deviceEntity.statementAccountId,
                  let encryptionPublicKey = deviceEntity.encryptionPublicKey else {
                return nil
            }
            return Chat.PeerDevice(
                statementAccountId: statementAccountId,
                encryptionPublicKey: encryptionPublicKey
            )
        } ?? []

        return Chat.Contact(
            accountId: accountId,
            username: username,
            publicKey: publicKey,
            pin: entity.pin,
            pushId: entity.pushId,
            pushToken: entity.pushToken,
            voipPushToken: entity.voipPushToken,
            peerPlatform: peerPlatform,
            lastOwnToken: entity.lastOwnToken,
            voipLastOwnToken: entity.voipLastOwnToken,
            chatRequest: chatRequest,
            ownKeyId: ownKeyId,
            imageData: entity.imageData,
            isBlocked: entity.isBlocked,
            devices: devices,
            pendingDevicesFanOut: entity.pendingDevicesFanOut,
            addedAt: entity.addedAt,
            acceptedAt: entity.acceptedAt
        )
    }

    func populate(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using context: NSManagedObjectContext
    ) throws {
        entity.identifier = model.identifier
        entity.username = model.username
        entity.publicKey = model.publicKey
        entity.pin = model.pin
        entity.pushId = model.pushId
        entity.pushToken = model.pushToken
        entity.voipPushToken = model.voipPushToken
        entity.pushPlatform = model.peerPlatform?.rawValue
        entity.lastOwnToken = model.lastOwnToken
        entity.voipLastOwnToken = model.voipLastOwnToken
        entity.ownSignKeyId = model.ownKeyId.signKeyId
        entity.ownEncryptionKeyId = model.ownKeyId.encryptionKeyId
        entity.imageData = model.imageData
        entity.isBlocked = model.isBlocked
        entity.pendingDevicesFanOut = model.pendingDevicesFanOut
        entity.addedAt = model.addedAt
        entity.acceptedAt = model.acceptedAt

        try populateDevices(entity: entity, from: model, using: context)
    }
}

extension ChatContactMapper {
    private func populateDevices(
        entity: CoreDataEntity,
        from model: DataProviderModel,
        using context: NSManagedObjectContext
    ) throws {
        // Never delete here: inactive rows are tombstones.
        let existingDevices = entity.devices as? Set<CDContactDevice> ?? []
        let storedAccountIds = Set(existingDevices.compactMap(\.statementAccountId))

        for device in model.devices where !storedAccountIds.contains(device.statementAccountId) {
            let deviceEntity = try context.insertNew(CDContactDevice.self)
            deviceEntity.statementAccountId = device.statementAccountId
            deviceEntity.encryptionPublicKey = device.encryptionPublicKey
            deviceEntity.contact = entity
            deviceEntity.status = Chat.ContactDeviceStatus.active.rawValue
            deviceEntity.markModified()
        }
    }
}

private extension Chat.Contact.Own {
    init(entity: CDChatContact) throws {
        guard let ownSignKeyId = entity.ownSignKeyId else {
            throw CoreDataMapperError.missingRequiredData(keyPath: "ownSignKeyId")
        }
        signKeyId = ownSignKeyId
        encryptionKeyId = entity.ownEncryptionKeyId ?? ChatEncryptionDomain.mainChat.rawValue
    }
}
