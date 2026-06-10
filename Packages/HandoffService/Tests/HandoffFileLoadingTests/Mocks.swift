import Foundation
import HandoffService
import SubstrateSdk
import NovaCrypto

// MARK: - Service

final class MockHandoffService: HandoffServicing, @unchecked Sendable {
    var storage: [Data: Data] = [:]
    private(set) var ackedHashes: [Data] = []
    private(set) var submitCallCount = 0
    private(set) var claimCallCount = 0

    var submitError: Error?
    var claimError: Error?

    @discardableResult
    func submitData(
        _ data: Data,
        from _: SenderProofProviding,
        recipients _: Set<MultiSigner>
    ) async throws -> SubmittedData {
        if let error = submitError { throw error }

        let hash = try data.blake2b32()
        storage[hash] = data
        submitCallCount += 1

        return SubmittedData(
            hash: hash,
            poolStatus: PoolStatus(entryCount: 1, totalBytes: data.count, maxBytes: 10_000_000)
        )
    }

    func claimData(
        by dataHash: Data,
        recipient _: RecipientProofProviding
    ) async throws -> Data? {
        if let error = claimError { throw error }
        claimCallCount += 1
        return storage[dataHash]
    }

    func acknowledgeReceivedData(
        by dataHash: Data,
        recipient _: RecipientProofProviding
    ) async throws {
        ackedHashes.append(dataHash)
    }

    func getPoolStatus() async throws -> PoolStatus {
        PoolStatus(entryCount: 0, totalBytes: 0, maxBytes: 10_000_000)
    }
}

// MARK: - Encryption

final class PassthroughEncryptor: FileEncrypting {
    func encrypt(_ data: Data) throws -> Data { data }
    func decrypt(_ encryptedData: Data) throws -> Data { encryptedData }
}

// MARK: - Proof

final class NoProofProvider: SenderProofProviding {
    func getProof(for _: FileHash) async throws -> SenderProof {
        SenderProof(
            sender: .sr25519(Data(repeating: 0, count: 32)),
            signature: .sr25519(data: Data(repeating: 0, count: 64))
        )
    }
}

final class MockRecipientProofProvider: RecipientProofProviding {
    func getProof(for _: Data, context _: Data) async throws -> MultiSignature {
        .sr25519(data: Data(repeating: 0, count: 64))
    }
}

// MARK: - Upload Store

final class MockUploadFileContext: UploadFileContextProtocol, @unchecked Sendable {
    let fileData: Data

    private(set) var savedChunks: [(hash: Data, uploadedSize: Int64)] = []
    private(set) var finishCalled: Bool?

    var resumeProgress: ResumeUploadInfo.Progress?

    init(fileData: Data) {
        self.fileData = fileData
    }

    func fetchResumeInfo() async throws -> ResumeUploadInfo {
        ResumeUploadInfo(fileSize: fileData.count, progress: resumeProgress)
    }

    func fetchChunk(after bytesCount: Int, size: Int) async throws -> Data {
        let end = min(bytesCount + size, fileData.count)
        return fileData.subdata(in: bytesCount ..< end)
    }

    func saveUploadedChunk(_ hash: Data, uploadedSize: Int64) async throws {
        savedChunks.append((hash: hash, uploadedSize: uploadedSize))
    }

    func finishUploading(_ fullFileUploaded: Bool) async throws {
        finishCalled = fullFileUploaded
    }
}

// MARK: - Download Store

final class MockDownloadFileContext: DownloadFileContextProtocol, @unchecked Sendable {
    let metadataHash: FileHash

    private(set) var savedMetadata: Data?
    private(set) var savedTotalChunks: Int?
    private(set) var appendedChunks: [(data: Data, index: Int)] = []
    private(set) var finishCalled: Bool?

    var resumeInfo: ResumeDownloadInfo?

    init(metadataHash: FileHash) {
        self.metadataHash = metadataHash
    }

    func saveMetadata(_ data: Data, totalChunks: Int) async throws {
        savedMetadata = data
        savedTotalChunks = totalChunks
    }

    func fetchResumeInfo() async throws -> ResumeDownloadInfo? {
        resumeInfo
    }

    func appendChunk(_ data: Data, at index: Int) async throws {
        appendedChunks.append((data: data, index: index))
    }

    func finishDownloading(_ fullFileDownloaded: Bool) async throws {
        finishCalled = fullFileDownloaded
    }

    func assembleFile() -> Data {
        appendedChunks.sorted { $0.index < $1.index }
            .reduce(Data()) { $0 + $1.data }
    }
}

// MARK: - Helpers

enum TestError: Error {
    case intentional
}
