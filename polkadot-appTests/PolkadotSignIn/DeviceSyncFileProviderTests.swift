@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

@Suite(.timeLimit(.minutes(1)))
final class DeviceSyncFileProviderTests {
    typealias Message = Chat.DeviceSyncFileMessage

    private let directory: URL
    private let flow = MockDevicePeerConnectionFlow(startResult: .success(()))

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSyncFileProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("A stored file is served as header, 60 KiB chunks from the offset, then completed")
    func servesStoredFileInChunks() async throws {
        let size = 2 * DeviceSyncFileProvider.chunkPayloadSize + 10
        let (file, location, contents) = try makeStoredFile(name: "f0", size: size)
        let provider = makeProvider(locations: [file: location])

        await provider.handle(Message.Request(requestId: 7, files: [.init(file: file, offset: 0)]))
        let sent = await flow.waitForSentFileMessageCount(5)

        #expect(sent.first == .header(.init(requestId: 7, fileIndex: 0, totalSize: UInt64(size))))
        #expect(sent.chunks.map(\.offset) == [0, 61_440, 122_880])
        #expect(sent.chunks.reduce(Data()) { $0 + $1.data } == contents)
        #expect(sent.last == .completed(requestId: 7))
    }

    @Test("Resume streams only the bytes after the requested offset")
    func resumesFromOffset() async throws {
        let (file, location, contents) = try makeStoredFile(name: "f0", size: 10_000)
        let provider = makeProvider(locations: [file: location])

        await provider.handle(Message.Request(requestId: 1, files: [.init(file: file, offset: 4_096)]))
        let sent = await flow.waitForSentFileMessageCount(3)

        #expect(sent.chunks.map(\.offset) == [4_096])
        #expect(sent.chunks.first?.data == contents.suffix(from: 4_096))
        #expect(sent.last == .completed(requestId: 1))
    }

    @Test("An offset at the end of the file gets only the header")
    func offsetAtEndSendsHeaderOnly() async throws {
        let (file, location, _) = try makeStoredFile(name: "f0", size: 100)
        let provider = makeProvider(locations: [file: location])

        await provider.handle(Message.Request(requestId: 1, files: [.init(file: file, offset: 100)]))
        let sent = await flow.waitForSentFileMessageCount(2)

        #expect(sent == [.header(.init(requestId: 1, fileIndex: 0, totalSize: 100)), .completed(requestId: 1)])
    }

    @Test("Files are served in request order, an unavailable one in place of its header")
    func mixesUnavailableAndStoredInOrder() async throws {
        let missing = makeReference("missing")
        let downloading = makeReference("downloading")
        let (stored, location, contents) = try makeStoredFile(name: "f2", size: 10)
        let provider = makeProvider(locations: [downloading: .unavailable(.downloading), stored: location])

        await provider.handle(Message.Request(
            requestId: 3,
            files: [
                .init(file: missing, offset: 0),
                .init(file: downloading, offset: 0),
                .init(file: stored, offset: 0)
            ]
        ))
        let sent = await flow.waitForSentFileMessageCount(5)

        #expect(sent == [
            .unavailable(.init(requestId: 3, fileIndex: 0, reason: .notStored)),
            .unavailable(.init(requestId: 3, fileIndex: 1, reason: .downloading)),
            .header(.init(requestId: 3, fileIndex: 2, totalSize: 10)),
            .chunk(.init(requestId: 3, fileIndex: 2, offset: 0, data: contents)),
            .completed(requestId: 3)
        ])
    }

    @Test("A file that disappears after its header is reported unavailable")
    func deletedFileAfterHeaderIsUnavailable() async throws {
        let file = makeReference("gone")
        let url = directory.appendingPathComponent("gone")
        let provider = makeProvider(locations: [file: .stored(url: url, size: 500)])

        await provider.handle(Message.Request(requestId: 4, files: [.init(file: file, offset: 0)]))
        let sent = await flow.waitForSentFileMessageCount(3)

        #expect(sent == [
            .header(.init(requestId: 4, fileIndex: 0, totalSize: 500)),
            .unavailable(.init(requestId: 4, fileIndex: 0, reason: .notStored)),
            .completed(requestId: 4)
        ])
    }

    @Test("Cancelling the request being served stops before the next chunk and still completes it")
    func cancelCurrentRequestStopsStreaming() async throws {
        let (first, firstLocation, _) = try makeStoredFile(name: "f0", size: 200_000)
        let (second, secondLocation, _) = try makeStoredFile(name: "f1", size: 10)
        let locator = MockDeviceSyncFileLocator(
            locations: [first: firstLocation, second: secondLocation],
            gatedFile: first
        )
        let provider = DeviceSyncFileProvider(flow: flow, locator: locator, logger: Logger.shared)

        await provider.handle(Message.Request(
            requestId: 5,
            files: [.init(file: first, offset: 0), .init(file: second, offset: 0)]
        ))
        _ = await locator.locateEvents.waitForCount(1)
        await provider.cancel(requestId: 5)
        locator.openGate()
        let sent = await flow.waitForSentFileMessageCount(2)

        #expect(sent == [.header(.init(requestId: 5, fileIndex: 0, totalSize: 200_000)), .completed(requestId: 5)])
    }

    @Test("A queued request is cancelled at once, while requests and availability don't wait for each other")
    func queuedCancelAndAvailabilityAreAnsweredImmediately() async throws {
        let (slow, slowLocation, _) = try makeStoredFile(name: "slow", size: 10)
        let (other, otherLocation, _) = try makeStoredFile(name: "other", size: 20)
        let locator = MockDeviceSyncFileLocator(
            locations: [slow: slowLocation, other: otherLocation],
            gatedFile: slow
        )
        let provider = DeviceSyncFileProvider(flow: flow, locator: locator, logger: Logger.shared)

        await provider.handle(Message.Request(requestId: 1, files: [.init(file: slow, offset: 0)]))
        await provider.handle(Message.Request(requestId: 2, files: [.init(file: other, offset: 0)]))
        _ = await locator.locateEvents.waitForCount(1)

        await provider.cancel(requestId: 2)
        await provider.handle(Message.AvailabilityRequest(requestId: 9, files: [other, makeReference("missing")]))
        let early = await flow.waitForSentFileMessageCount(2)

        #expect(early == [
            .completed(requestId: 2),
            .availabilityResponse(.init(
                requestId: 9,
                availability: [.available(totalSize: 20), .unavailable(.notStored)]
            ))
        ])

        locator.openGate()
        let all = await flow.waitForSentFileMessageCount(5)

        #expect(all.suffix(3).first == .header(.init(requestId: 1, fileIndex: 0, totalSize: 10)))
        #expect(all.last == .completed(requestId: 1))
    }
}

private extension DeviceSyncFileProviderTests {
    func makeProvider(locations: [Message.FileReference: DeviceSyncFileLocation]) -> DeviceSyncFileProvider {
        DeviceSyncFileProvider(
            flow: flow,
            locator: MockDeviceSyncFileLocator(locations: locations),
            logger: Logger.shared
        )
    }

    func makeReference(_ name: String) -> Message.FileReference {
        .messageAttachment(.init(messageId: "message-\(name)", identifier: Data(name.utf8)))
    }

    func makeStoredFile(
        name: String,
        size: Int
    ) throws -> (Message.FileReference, DeviceSyncFileLocation, Data) {
        let contents = try Data.randomOrError(of: size)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)

        return (makeReference(name), .stored(url: url, size: UInt64(size)), contents)
    }
}

private extension [Chat.DeviceSyncFileMessage] {
    var chunks: [Chat.DeviceSyncFileMessage.Chunk] {
        compactMap { message in
            guard case let .chunk(chunk) = message else { return nil }
            return chunk
        }
    }
}
