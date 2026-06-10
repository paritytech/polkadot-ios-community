import Foundation
import HandoffService
import Operation_iOS
import SDKLogger

actor DownloadFileContext {
    let metadataHash: FileHash
    let filename: String
    let attachmentsStore: AttachmentStoring
    let repository: AnyDataProviderRepository<MixnetDownload>
    let chunkIndexRepository: AnyDataProviderRepository<MixnetDownloadChunkIndex>
    let fileManager: FileManager
    let logger: LoggerProtocol

    private var fileHandle: FileHandle?

    init(
        metadataHash: FileHash,
        filename: String,
        attachmentsStore: AttachmentStoring,
        repository: AnyDataProviderRepository<MixnetDownload>,
        chunkIndexRepository: AnyDataProviderRepository<MixnetDownloadChunkIndex>,
        fileManager: FileManager = FileManager.default,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.metadataHash = metadataHash
        self.filename = filename
        self.attachmentsStore = attachmentsStore
        self.repository = repository
        self.chunkIndexRepository = chunkIndexRepository
        self.fileManager = fileManager
        self.logger = logger
    }
}

extension DownloadFileContext: DownloadFileContextProtocol {
    nonisolated var identifier: String { metadataHash.toHex() }

    func saveMetadata(_ data: Data, totalChunks: Int) async throws {
        let model = MixnetDownload(
            metadataHashHex: identifier,
            lastChunkIndex: -1,
            totalChunks: Int32(totalChunks),
            metadata: data,
            downloadedBytes: 0
        )

        try await repository.saveOperation({ [model] }, { [] }).asyncExecute()
    }

    func fetchResumeInfo() async throws -> ResumeDownloadInfo? {
        let id = identifier

        let optDownload = try await repository.fetchOperation(
            by: { id },
            options: RepositoryFetchOptions()
        )
        .asyncExecute()

        guard
            let download = optDownload,
            let metadata = download.metadata else {
            return nil
        }

        let actualFileSize = partialFileSize()

        let lastChunkIndex: Int?
        let downloadedBytes: Int

        if download.downloadedBytes > Int64(actualFileSize) {
            // DB is ahead of the file — the last chunk write was interrupted.
            // Roll back to the previous chunk so it gets re-downloaded.
            lastChunkIndex = download.lastChunkIndex > 0 ? Int(download.lastChunkIndex - 1) : nil
            downloadedBytes = actualFileSize

            logger.warning(
                "Download state mismatch: DB expects \(download.downloadedBytes) bytes "
                    + "but file has \(actualFileSize). Rolling back to chunk \(String(describing: lastChunkIndex))"
            )
        } else {
            lastChunkIndex = download.lastChunkIndex >= 0 ? Int(download.lastChunkIndex) : nil
            downloadedBytes = actualFileSize
        }

        logger.debug("Last chunk index: \(String(describing: lastChunkIndex)), downloaded bytes: \(downloadedBytes)")

        return ResumeDownloadInfo(
            metadata: metadata,
            lastChunkIndex: lastChunkIndex,
            downloadedBytes: downloadedBytes
        )
    }

    func appendChunk(_ data: Data, at index: Int) async throws {
        let handle = try getOrCreateHandle()
        let currentEnd = try handle.seekToEnd()

        let update = MixnetDownloadChunkIndex(
            metadataHashHex: identifier,
            lastChunkIndex: Int32(index),
            downloadedBytes: Int64(currentEnd) + Int64(data.count)
        )

        try await chunkIndexRepository.saveOperation({ [update] }, { [] }).asyncExecute()

        try handle.write(contentsOf: data)
        try handle.synchronize()

        logger.debug("Appended chunk: \(index)")
    }

    func finishDownloading(_ fullFileDownloaded: Bool) async throws {
        closeHandle()

        guard fullFileDownloaded else {
            return
        }

        try attachmentsStore.moveFile(from: partialFilename, to: filename)

        let id = identifier
        try await repository.saveOperation({ [] }, { [id] }).asyncExecute()
    }
}

private extension DownloadFileContext {
    var partialFilename: String {
        filename + ".part"
    }

    func getOrCreateHandle() throws -> FileHandle {
        if let fileHandle {
            return fileHandle
        }

        let url = attachmentsStore.fileURL(for: partialFilename)

        if !attachmentsStore.hasFile(for: partialFilename) {
            try attachmentsStore.createEmptyFile(for: partialFilename)
        }

        let handle = try FileHandle(forWritingTo: url)
        fileHandle = handle

        return handle
    }

    func partialFileSize() -> Int {
        let url = attachmentsStore.fileURL(for: partialFilename)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    func closeHandle() {
        if let fileHandle {
            try? fileHandle.close()
            self.fileHandle = nil
        }
    }
}
