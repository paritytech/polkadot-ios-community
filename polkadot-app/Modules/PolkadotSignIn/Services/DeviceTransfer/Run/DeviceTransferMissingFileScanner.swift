import Foundation
import Operation_iOS

protocol DeviceTransferMissingFileScanning {
    func missingFiles() async throws -> [DeviceSyncFileRequestItem]
}

final class DeviceTransferMissingFileScanner {
    private let messageRepositoryFactory: ChatMessageRepositoryMaking
    private let downloadsStore: AttachmentStoring

    init(messageRepositoryFactory: ChatMessageRepositoryMaking, downloadsStore: AttachmentStoring) {
        self.messageRepositoryFactory = messageRepositoryFactory
        self.downloadsStore = downloadsStore
    }
}

extension DeviceTransferMissingFileScanner: DeviceTransferMissingFileScanning {
    func missingFiles() async throws -> [DeviceSyncFileRequestItem] {
        let messages = try await messageRepositoryFactory
            .createRepository(
                forFilter: .messageByContentType(.richText),
                sortDescriptors: [NSSortDescriptor(key: #keyPath(CDChatMessage.timestamp), ascending: false)]
            )
            .fetchAllOperation(with: .init())
            .asyncExecute()

        return messages.flatMap(missingFiles(of:))
    }
}

private extension DeviceTransferMissingFileScanner {
    func missingFiles(of message: Chat.LocalMessage) -> [DeviceSyncFileRequestItem] {
        guard case let .richText(content) = message.content else { return [] }

        return (content.attachments ?? []).compactMap { attachment in
            guard
                case let .remoteDownloadable(fileVariant) = attachment,
                !downloadsStore.hasFile(for: fileVariant.filename)
            else {
                return nil
            }

            let attachmentId = Chat.DeviceSyncFileMessage.MessageAttachmentId(
                messageId: message.messageId,
                identifier: fileVariant.identifier
            )
            return DeviceSyncFileRequestItem(file: .messageAttachment(attachmentId), filename: fileVariant.filename)
        }
    }
}
