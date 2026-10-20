@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

final class DeviceSyncFileLocatorTests {
    typealias Message = Chat.DeviceSyncFileMessage

    private let directory: URL
    private let uploadsStore: AttachmentStore
    private let downloadsStore: AttachmentStore
    private let messageRepositoryFactory = MockChatMessageRepositoryFactory()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSyncFileLocatorTests-\(UUID().uuidString)", isDirectory: true)
        uploadsStore = AttachmentStore(baseDirectory: directory.appendingPathComponent("uploads"))
        downloadsStore = AttachmentStore(baseDirectory: directory.appendingPathComponent("downloads"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("A received file is located in downloads with its size")
    func receivedFileIsStored() async throws {
        let fileVariant = try makeFileVariant()
        try await saveMessage(id: "received", attachment: .remoteDownloadable(fileVariant))
        let url = try downloadsStore.store(attachment: Data(count: 1_234), filename: fileVariant.filename)

        let location = await makeLocator().locate(reference(messageId: "received", identifier: fileVariant.identifier))

        #expect(location == .stored(url: url, size: 1_234))
    }

    @Test(
        "A received file that only has a HOP or sibling partial is reported as downloading",
        arguments: [".part", ".sync.part"]
    )
    func partialDownloadIsDownloading(suffix: String) async throws {
        let fileVariant = try makeFileVariant()
        try await saveMessage(id: "partial", attachment: .remoteDownloadable(fileVariant))
        try downloadsStore.store(attachment: Data(count: 10), filename: fileVariant.filename + suffix)

        let location = await makeLocator().locate(reference(messageId: "partial", identifier: fileVariant.identifier))

        #expect(location == .unavailable(.downloading))
    }

    @Test("A received file that was never downloaded is not stored")
    func missingDownloadIsNotStored() async throws {
        let fileVariant = try makeFileVariant()
        try await saveMessage(id: "missing", attachment: .remoteDownloadable(fileVariant))

        let location = await makeLocator().locate(reference(messageId: "missing", identifier: fileVariant.identifier))

        #expect(location == .unavailable(.notStored))
    }

    @Test("An own upload is located in uploads by its HOP identifier")
    func ownUploadIsStored() async throws {
        let identifier = try Data.randomOrError(of: 32)
        try await saveMessage(id: "sent", attachment: makeUploadable(path: "original.mp4", identifier: identifier))
        let url = try uploadsStore.store(attachment: Data(count: 77), filename: "original.mp4")

        let location = await makeLocator().locate(reference(messageId: "sent", identifier: identifier))

        #expect(location == .stored(url: url, size: 77))
    }

    @Test(
        "Unknown messages and attachments that don't match are not stored",
        arguments: ["unknown-message", "sent"]
    )
    func unmatchedReferenceIsNotStored(messageId: String) async throws {
        try await saveMessage(id: "sent", attachment: makeUploadable(path: "original.mp4", identifier: nil))
        try uploadsStore.store(attachment: Data(count: 77), filename: "original.mp4")

        let location = await makeLocator().locate(reference(messageId: messageId, identifier: Data([1, 2])))

        #expect(location == .unavailable(.notStored))
    }
}

private extension DeviceSyncFileLocatorTests {
    func makeLocator() -> DeviceSyncFileLocator {
        DeviceSyncFileLocator(
            messageRepositoryFactory: messageRepositoryFactory,
            uploadsStore: uploadsStore,
            downloadsStore: downloadsStore,
            logger: Logger.shared
        )
    }

    func reference(messageId: String, identifier: Data) -> Message.FileReference {
        .messageAttachment(.init(messageId: messageId, identifier: identifier))
    }

    func makeFileVariant() throws -> ChatRemoteMessageContent.FileVariant {
        try .p2pMixnet(.init(
            identifier: Data.randomOrError(of: 32),
            claimTicket: Data.randomOrError(of: 32),
            node: .wssUrl("wss://hop.example"),
            meta: .general(.init(mimeType: "image/jpeg", fileSize: 1_234))
        ))
    }

    func makeUploadable(path: String, identifier: Data?) throws -> Chat.LocalMessage.Content.Attachment {
        let uploadingInfo = try identifier.map { identifier in
            try Chat.LocalMessage.Content.FileUploadingInfo.toPeer(.init(
                identifier: identifier,
                claimTicket: Data.randomOrError(of: 32),
                node: .wssUrl("wss://hop.example")
            ))
        }

        return .localUploadable(.init(
            relativeLocalPath: path,
            meta: .general(.init(mimeType: "video/mp4", fileSize: 77)),
            uploadingInfo: uploadingInfo
        ))
    }

    func saveMessage(id: String, attachment: Chat.LocalMessage.Content.Attachment) async throws {
        let message = Chat.LocalMessage(
            messageId: id,
            chatId: .person(Data(repeating: 7, count: 32)),
            origin: .user,
            creationSource: .deviceSync,
            status: .outgoing(.sent),
            timestamp: 1,
            content: .richText(.init(text: nil, attachments: [attachment])),
            reactions: [],
            compactionId: nil,
            relatedMessages: []
        )

        try await messageRepositoryFactory.save([message])
    }
}
