import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import AsyncExtensions
@testable import HandoffService

struct HandoffFileLoaderDownloadTests {
    let chunkSize = 100

    // MARK: - Tests

    @Test func freshDownloadCompletesSuccessfully() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        let progressEvents = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }
        let finishedEvents = events.compactMap { if case let .onFinished(h) = $0 { h } else { nil } }

        #expect(progressEvents.count == 3)
        #expect(finishedEvents.count == 1)
        #expect(finishedEvents.first == metadataHash)

        // All chunks downloaded and assembled correctly
        #expect(store.assembleFile() == fileData)
        #expect(store.finishCalled == true)
    }

    @Test func downloadSavesMetadataOnFreshStart() async throws {
        let fileData = try Data.randomOrError(of: 100)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        _ = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        #expect(store.savedMetadata != nil)
        #expect(store.savedTotalChunks == 1)
    }

    @Test func downloadAcknowledgesAfterEachChunk() async throws {
        let fileData = try Data.randomOrError(of: 200)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        _ = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        // 1 metadata ack + 2 chunk acks
        #expect(service.ackedHashes.count == 3)
        #expect(service.ackedHashes.first == metadataHash)
    }

    @Test func downloadEmitsCorrectProgress() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        let progress = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }

        #expect(progress[0].downloaded == 100)
        #expect(progress[0].total == 250)
        #expect(progress[1].downloaded == 200)
        #expect(progress[2].downloaded == 250)
    }

    @Test func downloadResumesFromLastChunk() async throws {
        let fileData = try Data.randomOrError(of: 300)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        // Build resume metadata matching what was stored
        let metadata = service.storage[metadataHash]!

        store.resumeInfo = ResumeDownloadInfo(
            metadata: metadata,
            lastChunkIndex: 1,
            downloadedBytes: 200
        )

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        let progress = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }

        // 1 initial resume progress + 1 remaining chunk = 2 progress events
        #expect(progress.count == 2)
        #expect(progress[0].downloaded == 200)
        #expect(progress[1].downloaded == 300)

        // Only 1 chunk claimed (chunk index 2), no metadata claim
        #expect(service.claimCallCount == 1)
        #expect(store.appendedChunks.count == 1)
        #expect(store.appendedChunks[0].index == 2)
        #expect(store.savedMetadata == nil)
    }

    @Test func downloadReturnsErrorForMissingMetadata() async throws {
        let (loader, _) = makeLoader()
        let fakeHash = try Data.randomOrError(of: 32)
        let store = MockDownloadFileContext(metadataHash: fakeHash)

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: fakeHash,
            claimer: makeClaimer(),
            store: store
        ))

        let hasNoMetadataError = events.contains {
            if case let .onError(error) = $0,
               let downloadError = error as? FileDownloadingError,
               case .noMetadata = downloadError {
                true
            } else {
                false
            }
        }

        #expect(hasNoMetadataError)
    }

    @Test func downloadReturnsErrorForMissingChunk() async throws {
        let fileData = try Data.randomOrError(of: 200)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)

        // Remove one chunk from the service so claim returns nil
        let metadata = service.storage[metadataHash]!
        let uploadedFile = try UploadedFile.scaleDecode(from: metadata)
        service.storage.removeValue(forKey: uploadedFile.chunks[1])

        let store = MockDownloadFileContext(metadataHash: metadataHash)

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        let hasNoChunkError = events.contains {
            if case let .onError(error) = $0,
               let downloadError = error as? FileDownloadingError,
               case .noChunk = downloadError {
                true
            } else {
                false
            }
        }

        #expect(hasNoChunkError)
        #expect(store.finishCalled == false)
    }

    @Test func downloadCallsFinishFalseOnError() async throws {
        let service = MockHandoffService()
        service.claimError = TestError.intentional
        let (loader, _) = makeLoader(service: service)
        let fakeHash = try Data.randomOrError(of: 32)
        let store = MockDownloadFileContext(metadataHash: fakeHash)

        let events = try await collectDownloadEvents(from: loader.downloadFile(
            using: fakeHash,
            claimer: makeClaimer(),
            store: store
        ))

        let hasError = events.contains { if case .onError = $0 { true } else { false } }

        #expect(hasError)
        #expect(store.finishCalled == false)
    }

    @Test func downloadAppendsChunksInOrder() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, service) = makeLoader()
        let metadataHash = try populateService(service, with: fileData)
        let store = MockDownloadFileContext(metadataHash: metadataHash)

        _ = try await collectDownloadEvents(from: loader.downloadFile(
            using: metadataHash,
            claimer: makeClaimer(),
            store: store
        ))

        #expect(store.appendedChunks.count == 3)
        #expect(store.appendedChunks[0].index == 0)
        #expect(store.appendedChunks[1].index == 1)
        #expect(store.appendedChunks[2].index == 2)
    }
}

private extension HandoffFileLoaderDownloadTests {
    func makeLoader(
        service: MockHandoffService = MockHandoffService()
    ) -> (HandoffFileLoader, MockHandoffService) {
        let loader = HandoffFileLoader(service: service)
        return (loader, service)
    }

    func makeClaimer() -> FileClaimer {
        FileClaimer(
            proofProvider: MockRecipientProofProvider(),
            decryptor: PassthroughEncryptor()
        )
    }

    func populateService(
        _ service: MockHandoffService,
        with fileData: Data
    ) throws -> Data {
        let chunks = fileData.chunked(by: chunkSize)

        var chunkHashes: [Data] = []

        for chunk in chunks {
            let hash = try chunk.blake2b32()
            service.storage[hash] = chunk
            chunkHashes.append(hash)
        }

        let uploadedFile = UploadedFile(totalSize: UInt64(fileData.count), chunks: chunkHashes)
        let metadata = try uploadedFile.scaleEncoded()
        let metadataHash = try metadata.blake2b32()
        service.storage[metadataHash] = metadata

        return metadataHash
    }

    func collectDownloadEvents(
        from stream: AnyAsyncSequence<FileDownloadingEvent>
    ) async throws -> [FileDownloadingEvent] {
        var events: [FileDownloadingEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}
