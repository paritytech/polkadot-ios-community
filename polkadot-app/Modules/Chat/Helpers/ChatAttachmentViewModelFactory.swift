import UIKit
import Foundation
import PolkadotUI
import UniformTypeIdentifiers
import Kingfisher
import Foundation_iOS

protocol ChatAttachmentViewModelMaking {
    func makeAttachmentItem(
        for attachment: Chat.LocalMessage.Content.Attachment,
        messageId: Chat.MessageId,
        onSelection: @escaping () -> Void
    ) -> ChatRichTextMessageConfiguration.AttachmentItem?
}

final class ChatAttachmentViewModelFactory {
    static var maxThumbnailSize: CGFloat {
        240 * UIScreen.main.scale
    }

    let uploadAttachmentStore: AttachmentStoring
    let attachmentUploadStateProvider: AttachmentLoadProgressProvidable
    let downloadAttachmentStore: AttachmentStoring
    let attachmentDownloadStateProvider: AttachmentLoadProgressProvidable
    let durationFormatter: TimeFormatterProtocol

    init(
        uploadAttachmentStore: AttachmentStoring,
        attachmentUploadStateProvider: AttachmentLoadProgressProvidable,
        downloadAttachmentStore: AttachmentStoring,
        attachmentDownloadStateProvider: AttachmentLoadProgressProvidable,
        durationFormatter: TimeFormatterProtocol = MinuteSecondFormatter()
    ) {
        self.uploadAttachmentStore = uploadAttachmentStore
        self.attachmentUploadStateProvider = attachmentUploadStateProvider
        self.downloadAttachmentStore = downloadAttachmentStore
        self.attachmentDownloadStateProvider = attachmentDownloadStateProvider
        self.durationFormatter = durationFormatter
    }
}

// MARK: - Private factory helpers

private extension ChatAttachmentViewModelFactory {
    func progressDrivenOverlayInfoProvider(
        needsLoading: Bool,
        service: AttachmentLoadProgressProvidable,
        attachmentId: AttachmentId,
        loadingDirection: LoadingDirection,
        successConfiguration: ChatMessageOverlayInfoViewConfiguration? = nil
    ) -> (any ChatMessageOverlayInfoProviding)? {
        guard needsLoading else {
            return successConfiguration.map { StaticChatMessageOverlayInfoProvider($0) }
        }
        let progressViewModel = AttachmentProgressViewModel(
            service: service,
            attachmentId: attachmentId,
            loadingDirection: loadingDirection
        )
        switch loadingDirection {
        case .upload:
            return ProgressDrivenOverlayInfoProvider.forUpload(
                progressViewModel: progressViewModel,
                successConfiguration: successConfiguration
            )
        case .download:
            return ProgressDrivenOverlayInfoProvider.forDownload(
                progressViewModel: progressViewModel,
                successConfiguration: successConfiguration
            )
        }
    }

    func progressDrivenButtonConfigurationProvider(
        needsLoading: Bool,
        service: AttachmentLoadProgressProvidable,
        attachmentId: AttachmentId,
        loadingDirection: LoadingDirection,
        successButtonConfiguration: ChatMessageMediaViewConfiguration.ButtonConfiguration?
    ) -> (any ChatMessageMediaButtonConfigurationProviding)? {
        guard needsLoading else {
            return successButtonConfiguration.map { StaticChatMessageMediaButtonConfigurationProvider($0) }
        }
        let progressViewModel = AttachmentProgressViewModel(
            service: service,
            attachmentId: attachmentId,
            loadingDirection: loadingDirection
        )
        return ProgressDrivenButtonConfigurationProvider(
            progressViewModel: progressViewModel,
            successConfiguration: successButtonConfiguration,
            emitProgressOnSubscription: true
        )
    }

    func createFromLocalUploadable(
        file: Chat.LocalMessage.Content.LocalUploadableFile,
        messageId: Chat.MessageId,
        onSelection: @escaping () -> Void
    ) -> ChatRichTextMessageConfiguration.AttachmentItem? {
        switch file.meta {
        case .image:
            let fileUrl = uploadAttachmentStore.fileURL(for: file.relativeLocalPath)

            let attachmentId = AttachmentId(
                messageId: messageId,
                fileId: file.relativeLocalPath
            )

            let imageViewModel = LocalImageViewModel(
                provider: ThumbnailImageDataProvider(
                    url: fileUrl,
                    maxPixelSize: Self.maxThumbnailSize
                )
            )

            let buttonConfigurationProvider = progressDrivenButtonConfigurationProvider(
                needsLoading: file.uploadingInfo == nil,
                service: attachmentUploadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .upload,
                successButtonConfiguration: nil
            )

            let topLeadingInfoProvider = progressDrivenOverlayInfoProvider(
                needsLoading: file.uploadingInfo == nil,
                service: attachmentUploadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .upload
            )

            // Corners are overridden later by the outer bubble composition based on tail side.
            let mediaConfiguration = ChatMessageMediaViewConfiguration(
                previewProvider: imageViewModel,
                topLeadingInfoProvider: topLeadingInfoProvider,
                buttonConfigurationProvider: buttonConfigurationProvider,
                tapOnMedia: onSelection
            )

            return ChatRichTextMessageConfiguration.AttachmentItem(
                identifier: attachmentId.stringValue,
                mediaConfiguration: mediaConfiguration
            )

        case let .video(videoMeta):
            let fileUrl = uploadAttachmentStore.fileURL(for: file.relativeLocalPath)

            let attachmentId = AttachmentId(
                messageId: messageId,
                fileId: file.relativeLocalPath
            )

            let imageViewModel = LocalImageViewModel(
                provider: AVAssetImageDataProvider(assetURL: fileUrl, time: .zero)
            )

            let duration = try? durationFormatter.string(from: TimeInterval(videoMeta.duration))
            let durationConfiguration: ChatMessageOverlayInfoViewConfiguration? = duration.map {
                .init(icon: nil, title: $0, backgroundColor: UIColor(resource: .black45))
            }

            let buttonConfigurationProvider = progressDrivenButtonConfigurationProvider(
                needsLoading: file.uploadingInfo == nil,
                service: attachmentUploadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .upload,
                successButtonConfiguration: .init(style: .play, action: onSelection)
            )

            let topLeadingInfoProvider = progressDrivenOverlayInfoProvider(
                needsLoading: file.uploadingInfo == nil,
                service: attachmentUploadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .upload,
                successConfiguration: durationConfiguration
            )

            // Corners are overridden later by the outer bubble composition based on tail side.
            let mediaConfiguration = ChatMessageMediaViewConfiguration(
                previewProvider: imageViewModel,
                topLeadingInfoProvider: topLeadingInfoProvider,
                buttonConfigurationProvider: buttonConfigurationProvider,
                tapOnMedia: onSelection
            )

            return ChatRichTextMessageConfiguration.AttachmentItem(
                identifier: attachmentId.stringValue,
                mediaConfiguration: mediaConfiguration
            )

        case .general:
            return nil
        }
    }

    func createFromRemoteDownloadable(
        variant: ChatRemoteMessageContent.FileVariant,
        messageId: Chat.MessageId,
        onSelection: @escaping () -> Void
    ) -> ChatRichTextMessageConfiguration.AttachmentItem? {
        let filename = variant.filename

        switch variant.meta {
        case .image:
            let fileUrl = downloadAttachmentStore.fileURL(for: filename)

            let attachmentId = AttachmentId(
                messageId: messageId,
                fileId: filename
            )

            let imageViewModel = LocalImageViewModel(
                provider: LoadableAttachmentImageProvider(
                    attachmentId: attachmentId,
                    innerProvider: ThumbnailImageDataProvider(
                        url: fileUrl,
                        maxPixelSize: Self.maxThumbnailSize
                    ),
                    service: attachmentDownloadStateProvider,
                    dataExistencePredicate: { [downloadAttachmentStore] in
                        downloadAttachmentStore.hasFile(for: filename)
                    }
                )
            )

            let buttonConfigurationProvider = progressDrivenButtonConfigurationProvider(
                needsLoading: !downloadAttachmentStore.hasFile(for: filename),
                service: attachmentDownloadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .download,
                successButtonConfiguration: nil
            )

            let topLeadingInfoProvider = progressDrivenOverlayInfoProvider(
                needsLoading: !downloadAttachmentStore.hasFile(for: filename),
                service: attachmentDownloadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .download
            )

            // Corners are overridden later by the outer bubble composition based on tail side.
            let mediaConfiguration = ChatMessageMediaViewConfiguration(
                previewProvider: imageViewModel,
                topLeadingInfoProvider: topLeadingInfoProvider,
                buttonConfigurationProvider: buttonConfigurationProvider,
                tapOnMedia: onSelection
            )

            return ChatRichTextMessageConfiguration.AttachmentItem(
                identifier: attachmentId.stringValue,
                mediaConfiguration: mediaConfiguration
            )

        case let .video(videoMeta):
            let fileUrl = downloadAttachmentStore.fileURL(for: filename)

            let attachmentId = AttachmentId(
                messageId: messageId,
                fileId: filename
            )

            let imageViewModel = LocalImageViewModel(
                provider: LoadableAttachmentImageProvider(
                    attachmentId: attachmentId,
                    innerProvider: AVAssetImageDataProvider(assetURL: fileUrl, time: .zero),
                    service: attachmentDownloadStateProvider,
                    dataExistencePredicate: { [downloadAttachmentStore] in
                        downloadAttachmentStore.hasFile(for: filename)
                    }
                )
            )

            let duration = try? durationFormatter.string(from: TimeInterval(videoMeta.duration))
            let durationConfiguration: ChatMessageOverlayInfoViewConfiguration? = duration.map {
                .init(icon: nil, title: $0, backgroundColor: UIColor(resource: .black45))
            }

            let buttonConfigurationProvider = progressDrivenButtonConfigurationProvider(
                needsLoading: !downloadAttachmentStore.hasFile(for: filename),
                service: attachmentDownloadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .download,
                successButtonConfiguration: .init(style: .play, action: onSelection)
            )

            let topLeadingInfoProvider = progressDrivenOverlayInfoProvider(
                needsLoading: !downloadAttachmentStore.hasFile(for: filename),
                service: attachmentDownloadStateProvider,
                attachmentId: attachmentId,
                loadingDirection: .download,
                successConfiguration: durationConfiguration
            )

            // Corners are overridden later by the outer bubble composition based on tail side.
            let mediaConfiguration = ChatMessageMediaViewConfiguration(
                previewProvider: imageViewModel,
                topLeadingInfoProvider: topLeadingInfoProvider,
                buttonConfigurationProvider: buttonConfigurationProvider,
                tapOnMedia: onSelection
            )

            return ChatRichTextMessageConfiguration.AttachmentItem(
                identifier: attachmentId.stringValue,
                mediaConfiguration: mediaConfiguration
            )

        case .general:
            return nil
        }
    }
}

extension ChatAttachmentViewModelFactory: ChatAttachmentViewModelMaking {
    func makeAttachmentItem(
        for attachment: Chat.LocalMessage.Content.Attachment,
        messageId: Chat.MessageId,
        onSelection: @escaping () -> Void
    ) -> ChatRichTextMessageConfiguration.AttachmentItem? {
        switch attachment {
        case let .localUploadable(file):
            createFromLocalUploadable(
                file: file,
                messageId: messageId,
                onSelection: onSelection
            )

        case let .remoteDownloadable(fileVariant):
            createFromRemoteDownloadable(
                variant: fileVariant,
                messageId: messageId,
                onSelection: onSelection
            )
        }
    }
}
