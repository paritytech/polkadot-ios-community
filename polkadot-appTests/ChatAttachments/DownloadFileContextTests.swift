import Foundation
import HandoffService
import Operation_iOS
import Testing

@testable import polkadot_app

@Suite("DownloadFileContext")
struct DownloadFileContextTests {
    private let facade = UserDataStorageTestFacade()

    private func makeTempStore() throws -> (store: AttachmentStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (AttachmentStore(fileManager: .default, baseDirectory: dir), dir)
    }

    private func removeTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeContext(
        metadataHash: Data = Data(repeating: 0xAA, count: 32),
        filename: String = "test-file.mp4",
        store: AttachmentStore? = nil,
        tempDir: URL? = nil
    ) throws -> (context: DownloadFileContext, dir: URL) {
        let (attachmentsStore, dir): (AttachmentStore, URL)

        if let store, let tempDir {
            (attachmentsStore, dir) = (store, tempDir)
        } else {
            (attachmentsStore, dir) = try makeTempStore()
        }

        let factory = MixnetDownloadRepositoryFactory(storageFacade: facade)

        let context = DownloadFileContext(
            metadataHash: metadataHash,
            filename: filename,
            attachmentsStore: attachmentsStore,
            repository: factory.createRepository(),
            chunkIndexRepository: factory.createChunkIndexRepository()
        )

        return (context, dir)
    }

    // MARK: - saveMetadata

    @Test("saveMetadata persists to DB and fetchResumeInfo returns it")
    func saveAndFetchMetadata() async throws {
        let (context, dir) = try makeContext()
        defer { removeTempDir(dir) }

        let metadata = Data("scale-encoded-metadata".utf8)

        try await context.saveMetadata(metadata, totalChunks: 5)

        let info = try #require(try await context.fetchResumeInfo())
        #expect(info.metadata == metadata)
        #expect(info.lastChunkIndex == nil)
        #expect(info.downloadedBytes == 0)
    }

    // MARK: - fetchResumeInfo

    @Test("fetchResumeInfo returns nil when no record exists")
    func fetchResumeInfoNil() async throws {
        let (context, dir) = try makeContext()
        defer { removeTempDir(dir) }

        let info = try await context.fetchResumeInfo()
        #expect(info == nil)
    }

    // MARK: - appendChunk

    @Test("appendChunk writes data to partial file and updates DB")
    func appendChunkWritesAndPersists() async throws {
        let (context, dir) = try makeContext()
        defer { removeTempDir(dir) }

        try await context.saveMetadata(Data("meta".utf8), totalChunks: 2)

        let chunk0 = Data(repeating: 0x01, count: 100)
        try await context.appendChunk(chunk0, at: 0)

        let info = try #require(try await context.fetchResumeInfo())
        #expect(info.lastChunkIndex == 0)
        #expect(info.downloadedBytes == 100)
    }

    @Test("appendChunk appends multiple chunks sequentially")
    func appendMultipleChunks() async throws {
        let (context, dir) = try makeContext()
        defer { removeTempDir(dir) }

        try await context.saveMetadata(Data("m".utf8), totalChunks: 3)

        try await context.appendChunk(Data(repeating: 0xAA, count: 50), at: 0)
        try await context.appendChunk(Data(repeating: 0xBB, count: 60), at: 1)
        try await context.appendChunk(Data(repeating: 0xCC, count: 40), at: 2)

        let info = try #require(try await context.fetchResumeInfo())
        #expect(info.lastChunkIndex == 2)
        #expect(info.downloadedBytes == 150)
    }

    // MARK: - DB-before-file ordering

    @Test("downloadedBytes in DB matches expected total after chunk")
    func downloadedBytesMatchesExpected() async throws {
        let (context, dir) = try makeContext()
        defer { removeTempDir(dir) }

        try await context.saveMetadata(Data("m".utf8), totalChunks: 2)

        try await context.appendChunk(Data(repeating: 0x01, count: 100), at: 0)
        try await context.appendChunk(Data(repeating: 0x02, count: 80), at: 1)

        let info = try #require(try await context.fetchResumeInfo())
        #expect(info.downloadedBytes == 180)
        #expect(info.lastChunkIndex == 1)
    }

    // MARK: - finishDownloading

    @Test("finishDownloading true moves file and deletes DB record")
    func finishDownloadingSuccess() async throws {
        let (store, dir) = try makeTempStore()
        defer { removeTempDir(dir) }

        let (context, _) = try makeContext(filename: "video.mp4", store: store, tempDir: dir)

        try await context.saveMetadata(Data("m".utf8), totalChunks: 1)
        try await context.appendChunk(Data(repeating: 0xFF, count: 50), at: 0)
        try await context.finishDownloading(true)

        #expect(store.hasFile(for: "video.mp4"))
        #expect(!store.hasFile(for: "video.mp4.part"))

        let info = try await context.fetchResumeInfo()
        #expect(info == nil)
    }

    @Test("finishDownloading false keeps partial file and DB record")
    func finishDownloadingFailure() async throws {
        let (store, dir) = try makeTempStore()
        defer { removeTempDir(dir) }

        let (context, _) = try makeContext(filename: "video.mp4", store: store, tempDir: dir)

        try await context.saveMetadata(Data("m".utf8), totalChunks: 2)
        try await context.appendChunk(Data(repeating: 0x01, count: 50), at: 0)
        try await context.finishDownloading(false)

        #expect(store.hasFile(for: "video.mp4.part"))
        #expect(!store.hasFile(for: "video.mp4"))

        let info = try await context.fetchResumeInfo()
        #expect(info != nil)
    }

    // MARK: - Resume mismatch detection

    @Test("fetchResumeInfo rolls back chunk when DB ahead of file")
    func resumeMismatchRollsBack() async throws {
        let (store, dir) = try makeTempStore()
        defer { removeTempDir(dir) }

        let metadataHash = Data(repeating: 0xBB, count: 32)

        let (context1, _) = try makeContext(metadataHash: metadataHash, store: store, tempDir: dir)
        try await context1.saveMetadata(Data("m".utf8), totalChunks: 3)

        try await context1.appendChunk(Data(repeating: 0x01, count: 100), at: 0)
        try await context1.appendChunk(Data(repeating: 0x02, count: 100), at: 1)

        // Simulate: chunk 2 was saved to DB but file write didn't complete
        let factory = MixnetDownloadRepositoryFactory(storageFacade: facade)
        let chunkRepo = factory.createChunkIndexRepository()
        let update = MixnetDownloadChunkIndex(
            metadataHashHex: metadataHash.toHex(),
            lastChunkIndex: 2,
            downloadedBytes: 300
        )
        try await chunkRepo.saveOperation({ [update] }, { [] }).asyncExecute()

        // New context on "relaunch" — file has 200 bytes but DB says 300
        let (context2, _) = try makeContext(metadataHash: metadataHash, store: store, tempDir: dir)
        let info = try #require(try await context2.fetchResumeInfo())

        #expect(info.lastChunkIndex == 1)
        #expect(info.downloadedBytes == 200)
    }

    @Test("fetchResumeInfo rolls back to nil when first chunk DB ahead of file")
    func resumeMismatchFirstChunk() async throws {
        let (store, dir) = try makeTempStore()
        defer { removeTempDir(dir) }

        let metadataHash = Data(repeating: 0xDD, count: 32)

        let (context, _) = try makeContext(metadataHash: metadataHash, store: store, tempDir: dir)
        try await context.saveMetadata(Data("m".utf8), totalChunks: 2)

        // DB says chunk 0 written with 100 bytes, but file is empty (0 bytes)
        let factory = MixnetDownloadRepositoryFactory(storageFacade: facade)
        let chunkRepo = factory.createChunkIndexRepository()
        let update = MixnetDownloadChunkIndex(
            metadataHashHex: metadataHash.toHex(),
            lastChunkIndex: 0,
            downloadedBytes: 100
        )
        try await chunkRepo.saveOperation({ [update] }, { [] }).asyncExecute()

        let info = try #require(try await context.fetchResumeInfo())
        #expect(info.lastChunkIndex == nil)
        #expect(info.downloadedBytes == 0)
    }
}
