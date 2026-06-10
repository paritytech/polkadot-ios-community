import Testing
import Foundation
import SubstrateSdk
import NovaCrypto
import AsyncExtensions
@testable import HandoffService

struct HandoffFileLoaderUploadTests {
    let chunkSize = 100
    let dummyPubKey = MultiSigner.sr25519(Data(repeating: 1, count: 32))

    // MARK: - Tests

    @Test func freshUploadCompletesSuccessfully() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, service) = makeLoader()
        let store = MockUploadFileContext(fileData: fileData)

        let events = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        // 3 chunks (100 + 100 + 50) → 3 progress + 1 finished
        let progressEvents = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }
        let finishedEvents = events.compactMap { if case let .onFinished(f) = $0 { f } else { nil } }

        #expect(progressEvents.count == 3)
        #expect(finishedEvents.count == 1)

        // 3 chunks + 1 metadata = 4 submits
        #expect(service.submitCallCount == 4)

        // Each chunk saved to store
        #expect(store.savedChunks.count == 3)
        #expect(store.finishCalled == true)
    }

    @Test func uploadEmitsCorrectProgress() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, _) = makeLoader()
        let store = MockUploadFileContext(fileData: fileData)

        let events = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        let progressValues = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }

        #expect(progressValues[0].uploaded == 100)
        #expect(progressValues[0].total == 250)
        #expect(progressValues[0].uploadedHashes.count == 1)

        #expect(progressValues[1].uploaded == 200)
        #expect(progressValues[1].uploadedHashes.count == 2)

        #expect(progressValues[2].uploaded == 250)
        #expect(progressValues[2].uploadedHashes.count == 3)
    }

    @Test func uploadResumesFromProgress() async throws {
        let fileData = try Data.randomOrError(of: 250)
        let (loader, service) = makeLoader()
        let store = MockUploadFileContext(fileData: fileData)

        // Simulate 2 chunks already uploaded
        let chunk0Hash = try fileData.subdata(in: 0 ..< 100).blake2b32()
        let chunk1Hash = try fileData.subdata(in: 100 ..< 200).blake2b32()

        store.resumeProgress = .init(
            uploadedHashes: [chunk0Hash, chunk1Hash],
            uploadedSize: 200
        )

        let events = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        let progressValues = events.compactMap { if case let .onProgress(p) = $0 { p } else { nil } }

        // 1 initial resume progress + 1 chunk remaining = 2 progress events
        #expect(progressValues.count == 2)

        // Only 1 chunk submitted + 1 metadata = 2 submits
        #expect(service.submitCallCount == 2)

        // Only 1 new chunk saved
        #expect(store.savedChunks.count == 1)
        #expect(store.finishCalled == true)
    }

    @Test func uploadSavesChunkHashAfterEachSubmit() async throws {
        let fileData = try Data.randomOrError(of: 200)
        let (loader, _) = makeLoader()
        let store = MockUploadFileContext(fileData: fileData)

        _ = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        #expect(store.savedChunks.count == 2)
        #expect(store.savedChunks[0].uploadedSize == 100)
        #expect(store.savedChunks[1].uploadedSize == 200)
    }

    @Test func uploadCallsFinishFalseOnError() async throws {
        let fileData = try Data.randomOrError(of: 100)
        let service = MockHandoffService()
        service.submitError = TestError.intentional
        let (loader, _) = makeLoader(service: service)
        let store = MockUploadFileContext(fileData: fileData)

        let events = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        let hasError = events.contains { if case .onError = $0 { true } else { false } }

        #expect(hasError)
        #expect(store.finishCalled == false)
    }

    @Test func uploadMetadataContainsAllChunkHashes() async throws {
        let fileData = try Data.randomOrError(of: 200)
        let (loader, service) = makeLoader()
        let store = MockUploadFileContext(fileData: fileData)

        let events = try await collectUploadEvents(from: loader.uploadFile(
            store: store,
            sender: NoProofProvider(),
            recipients: makeRecipients()
        ))

        let metadataHash = events.compactMap { if case let .onFinished(f) = $0 { f.metadataHash } else { nil } }.first!

        // Decode the stored metadata
        let metadataData = service.storage[metadataHash]!
        let uploadedFile = try UploadedFile.scaleDecode(from: metadataData)

        #expect(uploadedFile.chunks.count == 2)
        #expect(uploadedFile.totalSize == 200)
    }
}

private extension HandoffFileLoaderUploadTests {
    func makeLoader(service: MockHandoffService = MockHandoffService()) -> (HandoffFileLoader, MockHandoffService) {
        let loader = HandoffFileLoader(service: service, chunkSize: chunkSize)
        return (loader, service)
    }

    func makeRecipients() -> FileRecipients {
        FileRecipients(pubKeys: [dummyPubKey], encryptor: PassthroughEncryptor())
    }

    func collectUploadEvents(
        from stream: AnyAsyncSequence<FileUploadingEvent>
    ) async throws -> [FileUploadingEvent] {
        var events: [FileUploadingEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}
