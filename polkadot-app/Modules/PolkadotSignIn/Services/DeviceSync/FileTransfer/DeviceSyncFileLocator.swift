import Foundation
import Operation_iOS

enum DeviceSyncFileLocation: Equatable {
    case stored(url: URL, size: UInt64)
    case unavailable(Chat.DeviceSyncFileMessage.UnavailableReason)
}

protocol DeviceSyncFileLocating: Sendable {
    func locate(_ file: Chat.DeviceSyncFileMessage.FileReference) async -> DeviceSyncFileLocation
}

/// Resolves a requested attachment through its message row: an own original from `ChatUploads`,
/// a received file from `ChatDownloads`, or a reason why it can't be served.
final class DeviceSyncFileLocator {
    private static let partialSuffixes = [".part", DeviceSyncFileWriter.partialSuffix]

    private let messageRepositoryFactory: ChatMessageRepositoryMaking
    private let uploadsStore: AttachmentStoring
    private let downloadsStore: AttachmentStoring
    private let fileManager: FileManager
    private let logger: LoggerProtocol

    init(
        messageRepositoryFactory: ChatMessageRepositoryMaking,
        uploadsStore: AttachmentStoring,
        downloadsStore: AttachmentStoring,
        fileManager: FileManager = .default,
        logger: LoggerProtocol
    ) {
        self.messageRepositoryFactory = messageRepositoryFactory
        self.uploadsStore = uploadsStore
        self.downloadsStore = downloadsStore
        self.fileManager = fileManager
        self.logger = logger
    }
}

extension DeviceSyncFileLocator: @unchecked Sendable {}

extension DeviceSyncFileLocator: DeviceSyncFileLocating {
    func locate(_ file: Chat.DeviceSyncFileMessage.FileReference) async -> DeviceSyncFileLocation {
        switch file {
        case let .messageAttachment(attachmentId):
            await locateAttachment(attachmentId)
        }
    }
}

private extension DeviceSyncFileLocator {
    func locateAttachment(
        _ attachmentId: Chat.DeviceSyncFileMessage.MessageAttachmentId
    ) async -> DeviceSyncFileLocation {
        let message: Chat.LocalMessage?

        do {
            message = try await messageRepositoryFactory
                .createRepository(forFilter: nil)
                .fetchOperation(by: { attachmentId.messageId }, options: .init())
                .asyncExecute()
        } catch {
            logger.error("Sync file message lookup failed: \(error)")
            return .unavailable(.notStored)
        }

        guard
            case let .richText(content) = message?.content,
            let attachment = content.attachments?.first(where: { $0.matches(attachmentId.identifier) })
        else {
            return .unavailable(.notStored)
        }

        return location(of: attachment)
    }

    func location(of attachment: Chat.LocalMessage.Content.Attachment) -> DeviceSyncFileLocation {
        switch attachment {
        case let .localUploadable(file):
            return storedLocation(of: file.relativeLocalPath, in: uploadsStore) ?? .unavailable(.notStored)
        case let .remoteDownloadable(fileVariant):
            if let location = storedLocation(of: fileVariant.filename, in: downloadsStore) {
                return location
            }

            let isDownloading = Self.partialSuffixes.contains { suffix in
                downloadsStore.hasFile(for: fileVariant.filename + suffix)
            }
            return .unavailable(isDownloading ? .downloading : .notStored)
        }
    }

    func storedLocation(of filename: String, in store: AttachmentStoring) -> DeviceSyncFileLocation? {
        guard store.hasFile(for: filename) else { return nil }

        let url = store.fileURL(for: filename)

        guard let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }

        return .stored(url: url, size: size.uint64Value)
    }
}

private extension Chat.LocalMessage.Content.Attachment {
    func matches(_ identifier: Data) -> Bool {
        switch self {
        case let .remoteDownloadable(fileVariant):
            fileVariant.identifier == identifier
        case let .localUploadable(file):
            switch file.uploadingInfo {
            case let .toPeer(info):
                info.identifier == identifier
            case nil:
                false
            }
        }
    }
}
