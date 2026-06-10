import Foundation
import HandoffService

final class MockDownloadFileContext: DownloadFileContextProtocol {
    let metadataHash: FileHash

    private var metadataBlob: Data?
    private var fileData = Data()
    private var lastIndex: Int?
    private(set) var isFinished = false

    init(metadataHash: FileHash) {
        self.metadataHash = metadataHash
    }

    func saveMetadata(_ data: Data, totalChunks _: Int) async throws {
        metadataBlob = data
    }

    func fetchResumeInfo() async throws -> ResumeDownloadInfo? {
        guard let metadataBlob else { return nil }

        return ResumeDownloadInfo(
            metadata: metadataBlob,
            lastChunkIndex: lastIndex,
            downloadedBytes: fileData.count
        )
    }

    func appendChunk(_ data: Data, at index: Int) async throws {
        fileData.append(data)
        lastIndex = index
    }

    func finishDownloading(_ fullFileDownloaded: Bool) async throws {
        isFinished = fullFileDownloaded
    }

    func assembleFile() -> Data {
        fileData
    }
}
