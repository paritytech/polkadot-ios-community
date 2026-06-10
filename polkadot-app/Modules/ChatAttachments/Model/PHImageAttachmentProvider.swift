import Foundation
import UIKit
import UniformTypeIdentifiers

enum PHImageAttachmentProviderError: Error {
    case failedToLoadImage
    case downsamplingFailed
    case compressionFailed
    case fileSaveFailed
}

final class PHImageAttachmentProvider: @unchecked Sendable {
    let itemProvider: NSItemProvider

    private let previewSize: CGFloat = 600
    private let uploadSize: CGFloat = 4_800
    private let compressionQuality: CGFloat = 0.7

    init(itemProvider: NSItemProvider) {
        self.itemProvider = itemProvider
    }
}

private extension PHImageAttachmentProvider {
    func processAttachment(from url: URL, store: AttachmentStoring) throws -> ProcessedAttachment {
        guard
            let imageToUpload = UIImage.downsampleImage(
                at: url,
                maxSideSize: uploadSize,
                scale: 1
            )
        else {
            throw PHImageAttachmentProviderError.downsamplingFailed
        }

        guard let uploadData = imageToUpload.jpegData(compressionQuality: compressionQuality) else {
            throw PHImageAttachmentProviderError.compressionFailed
        }

        let ext = url.pathExtension

        guard let fileName = (UUID().uuidString as NSString).appendingPathExtension(ext) else {
            throw PHImageAttachmentProviderError.fileSaveFailed
        }

        try store.store(attachment: uploadData, filename: fileName)

        let fileUrl = store.fileURL(for: fileName)

        let imageMeta = ChatRemoteMessageContent.ImageFileMeta(
            general: .init(
                mimeType: AttachmentMimeType.jpegImage,
                fileSize: UInt32(uploadData.count)
            ),
            width: UInt32(imageToUpload.size.width * imageToUpload.scale),
            height: UInt32(imageToUpload.size.height * imageToUpload.scale),
            thumbnail: nil
        )

        return ProcessedAttachment(
            fileId: fileName,
            fileUrl: fileUrl,
            meta: .image(imageMeta)
        )
    }
}

extension PHImageAttachmentProvider: ChatAttachmentProviding {
    var neededAudioActivity: AudioSessionActivity? {
        nil
    }

    func prepareForSend(using store: AttachmentStoring) async throws -> ProcessedAttachment {
        try await withCheckedThrowingContinuation { continuation in
            itemProvider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { [weak self, store] url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sourceUrl = url, let self else {
                    continuation.resume(throwing: PHImageAttachmentProviderError.failedToLoadImage)
                    return
                }

                do {
                    let attachment = try processAttachment(
                        from: sourceUrl,
                        store: store
                    )

                    continuation.resume(returning: attachment)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
