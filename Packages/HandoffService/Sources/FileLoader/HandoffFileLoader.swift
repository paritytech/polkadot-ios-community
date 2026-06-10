import Foundation
import AsyncExtensions

public protocol HandoffFileLoading {
    func uploadFile(
        store: UploadFileContextProtocol,
        sender: SenderProofProviding,
        recipients: FileRecipients
    ) -> AnyAsyncSequence<FileUploadingEvent>

    func downloadFile(
        using metadataHash: FileHash,
        claimer: FileClaimer,
        store: DownloadFileContextProtocol
    ) -> AnyAsyncSequence<FileDownloadingEvent>
}

public final class HandoffFileLoader {
    public let chunkSize: Int
    public let service: HandoffServicing

    public init(service: HandoffServicing, chunkSize: Int = 2_000_000) {
        self.service = service
        self.chunkSize = chunkSize
    }
}

extension HandoffFileLoader: HandoffFileLoading {
    public func uploadFile(
        store: UploadFileContextProtocol,
        sender: SenderProofProviding,
        recipients: FileRecipients
    ) -> AnyAsyncSequence<FileUploadingEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let resumeInfo = try await store.fetchResumeInfo()

                    let hashes = try await self.resumeUploading(
                        resumeInfo: resumeInfo,
                        store: store,
                        sender: sender,
                        recipients: recipients,
                        continuation: continuation
                    )

                    let uploadedFile = UploadedFile(
                        totalSize: UInt64(resumeInfo.fileSize),
                        chunks: hashes
                    )

                    let metadata = try uploadedFile.scaleEncoded()
                    let encryptedMetadata = try recipients.encryptor.encrypt(metadata)

                    let submittedData = try await self.service.submitData(
                        encryptedMetadata,
                        from: sender,
                        recipients: recipients.pubKeys
                    )

                    try await store.finishUploading(true)

                    continuation.yield(.onFinished(.init(metadataHash: submittedData.hash)))
                    continuation.finish()
                } catch {
                    try? await store.finishUploading(false)

                    guard !Task.isCancelled else { return }

                    continuation.yield(.onError(error))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        .eraseToAnyAsyncSequence()
    }

    public func downloadFile(
        using metadataHash: FileHash,
        claimer: FileClaimer,
        store: DownloadFileContextProtocol
    ) -> AnyAsyncSequence<FileDownloadingEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let resumeInfo = try await self.deriveDownloadMetadata(
                        for: metadataHash,
                        claimer: claimer,
                        store: store
                    )

                    guard let resumeInfo else {
                        continuation.yield(.onError(FileDownloadingError.noMetadata(metadataHash)))
                        continuation.finish()
                        return
                    }

                    try await self.resumeDownloading(
                        resumeInfo: resumeInfo,
                        claimer: claimer,
                        store: store,
                        continuation: continuation
                    )

                    try await store.finishDownloading(true)

                    continuation.yield(.onFinished(metadataHash))
                    continuation.finish()
                } catch {
                    try? await store.finishDownloading(false)

                    guard !Task.isCancelled else { return }

                    continuation.yield(.onError(error))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        .eraseToAnyAsyncSequence()
    }
}

// MARK: - Upload

private extension HandoffFileLoader {
    @discardableResult
    func resumeUploading(
        resumeInfo: ResumeUploadInfo,
        store: UploadFileContextProtocol,
        sender: SenderProofProviding,
        recipients: FileRecipients,
        continuation: AsyncStream<FileUploadingEvent>.Continuation
    ) async throws -> [Data] {
        let fileSize = resumeInfo.fileSize
        var hashes = resumeInfo.progress?.uploadedHashes ?? []
        var totalUploaded = resumeInfo.progress?.uploadedSize ?? 0

        if totalUploaded > 0 {
            continuation.yield(.onProgress(.init(
                uploaded: totalUploaded,
                total: fileSize,
                uploadedHashes: hashes
            )))
        }

        while totalUploaded < fileSize {
            try Task.checkCancellation()

            let remaining = fileSize - totalUploaded
            let currentChunkSize = min(chunkSize, remaining)
            let chunk = try await store.fetchChunk(
                after: totalUploaded,
                size: currentChunkSize
            )

            let encryptedChunk = try recipients.encryptor.encrypt(chunk)
            let submittedData = try await service.submitData(
                encryptedChunk,
                from: sender,
                recipients: recipients.pubKeys
            )

            hashes.append(submittedData.hash)
            totalUploaded += chunk.count

            try await store.saveUploadedChunk(
                submittedData.hash,
                uploadedSize: Int64(totalUploaded)
            )

            continuation.yield(.onProgress(.init(
                uploaded: totalUploaded,
                total: fileSize,
                uploadedHashes: hashes
            )))
        }

        return hashes
    }
}

// MARK: - Download

private extension HandoffFileLoader {
    struct DecodedResumeDownloadInfo {
        let metadata: DownloadFileMetadata
        let lastChunkIndex: Int?
        let downloadedBytes: Int
    }

    func deriveDownloadMetadata(
        for metadataHash: FileHash,
        claimer: FileClaimer,
        store: DownloadFileContextProtocol
    ) async throws -> DecodedResumeDownloadInfo? {
        if let resumeInfo = try await store.fetchResumeInfo() {
            let uploadedFile = try UploadedFile.scaleDecode(from: resumeInfo.metadata)
            let metadata = DownloadFileMetadata(
                totalSize: uploadedFile.totalSize,
                chunkHashes: uploadedFile.chunks
            )
            return DecodedResumeDownloadInfo(
                metadata: metadata,
                lastChunkIndex: resumeInfo.lastChunkIndex,
                downloadedBytes: resumeInfo.downloadedBytes
            )
        }

        guard
            let encryptedMetadata = try await service.claimData(
                by: metadataHash,
                recipient: claimer.proofProvider
            ) else {
            return nil
        }

        let decryptedMetadata = try claimer.decryptor.decrypt(encryptedMetadata)
        let uploadedFile = try UploadedFile.scaleDecode(from: decryptedMetadata)

        try await store.saveMetadata(
            decryptedMetadata,
            totalChunks: uploadedFile.chunks.count
        )

        try await service.acknowledgeReceivedData(
            by: metadataHash,
            recipient: claimer.proofProvider
        )

        let metadata = DownloadFileMetadata(
            totalSize: uploadedFile.totalSize,
            chunkHashes: uploadedFile.chunks
        )

        return DecodedResumeDownloadInfo(
            metadata: metadata,
            lastChunkIndex: nil,
            downloadedBytes: 0
        )
    }

    func resumeDownloading(
        resumeInfo: DecodedResumeDownloadInfo,
        claimer: FileClaimer,
        store: DownloadFileContextProtocol,
        continuation: AsyncStream<FileDownloadingEvent>.Continuation
    ) async throws {
        let totalSize = Int(resumeInfo.metadata.totalSize)
        let totalChunks = resumeInfo.metadata.chunkHashes.count
        let startIndex = resumeInfo.lastChunkIndex.map { $0 + 1 } ?? 0

        var downloadedBytes = resumeInfo.downloadedBytes

        if startIndex > 0 {
            continuation.yield(.onProgress(.init(
                downloaded: downloadedBytes,
                total: totalSize
            )))
        }

        for index in startIndex ..< totalChunks {
            try Task.checkCancellation()

            let chunkHash = resumeInfo.metadata.chunkHashes[index]

            guard
                let encryptedChunk = try await service.claimData(
                    by: chunkHash,
                    recipient: claimer.proofProvider
                ) else {
                throw FileDownloadingError.noChunk(chunkHash)
            }

            let chunk = try claimer.decryptor.decrypt(encryptedChunk)
            try await store.appendChunk(chunk, at: index)

            try await service.acknowledgeReceivedData(
                by: chunkHash,
                recipient: claimer.proofProvider
            )

            downloadedBytes += chunk.count

            continuation.yield(.onProgress(.init(
                downloaded: downloadedBytes,
                total: totalSize
            )))
        }
    }
}
