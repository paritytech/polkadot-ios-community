import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("MixnetDownloadMapper")
    struct MixnetDownloadMapperTests {
        private let facade = UserDataStorageTestFacade()

        private var repo: AnyDataProviderRepository<MixnetDownload> {
            facade.makeRepo(mapper: MixnetDownloadMapper())
        }

        private var chunkIndexRepo: AnyDataProviderRepository<MixnetDownloadChunkIndex> {
            facade.makeRepo(mapper: MixnetDownloadChunkIndexMapper())
        }

        @Test("roundTrip preserves all fields")
        func roundTrip() async throws {
            let metadata = Data("test-metadata".utf8)
            let original = MixnetDownload(
                metadataHashHex: "aabb01",
                lastChunkIndex: 3,
                totalChunks: 10,
                metadata: metadata,
                downloadedBytes: 4_096
            )

            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(
                    by: { original.identifier },
                    options: .init()
                ).asyncExecute()
            )

            #expect(result.metadataHashHex == original.metadataHashHex)
            #expect(result.lastChunkIndex == original.lastChunkIndex)
            #expect(result.totalChunks == original.totalChunks)
            #expect(result.metadata == metadata)
            #expect(result.downloadedBytes == original.downloadedBytes)
        }

        @Test("chunkIndex mapper updates existing entity")
        func chunkIndexUpdatesEntity() async throws {
            let original = MixnetDownload(
                metadataHashHex: "dd01",
                lastChunkIndex: -1,
                totalChunks: 5,
                metadata: Data("meta".utf8),
                downloadedBytes: 0
            )

            try await repo.saveOperation({ [original] }, { [] }).asyncExecute()

            let update = MixnetDownloadChunkIndex(
                metadataHashHex: "dd01",
                lastChunkIndex: 2,
                downloadedBytes: 2_048
            )

            try await chunkIndexRepo.saveOperation({ [update] }, { [] }).asyncExecute()

            let result = try #require(
                try await repo.fetchOperation(
                    by: { original.identifier },
                    options: .init()
                ).asyncExecute()
            )

            #expect(result.lastChunkIndex == 2)
            #expect(result.downloadedBytes == 2_048)
            #expect(result.metadata == Data("meta".utf8))
            #expect(result.totalChunks == 5)
        }

        @Test("chunkIndex mapper throws for missing entity")
        func chunkIndexThrowsForMissing() async throws {
            let update = MixnetDownloadChunkIndex(
                metadataHashHex: "nonexistent",
                lastChunkIndex: 0,
                downloadedBytes: 100
            )

            await #expect(throws: MixnetDownloadMapperError.self) {
                try await chunkIndexRepo.saveOperation({ [update] }, { [] }).asyncExecute()
            }
        }
    }
}
