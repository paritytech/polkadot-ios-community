@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

@Suite(.timeLimit(.minutes(1)))
final class DeviceSyncFileRequesterTests {
    typealias Message = Chat.DeviceSyncFileMessage

    private let directory: URL
    private let store: AttachmentStore
    private let flow = MockDevicePeerConnectionFlow(startResult: .success(()))
    private let sleeper = ManualDeviceSyncSleeper()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSyncFileRequesterTests-\(UUID().uuidString)", isDirectory: true)
        store = AttachmentStore(baseDirectory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Header and chunks complete the file, which is moved into the downloads store")
    func completesFile() async throws {
        let contents = try Data.randomOrError(of: 150)
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg")]) }
        let request = try await sentRequest()
        await requester.handle(.header(.init(requestId: request.requestId, fileIndex: 0, totalSize: 150)))
        await requester.handle(chunk(request, offset: 0, data: contents.prefix(100)))
        await requester.handle(chunk(request, offset: 100, data: contents.suffix(from: 100)))
        await requester.handle(.completed(requestId: request.requestId))

        #expect(await outcomes.value == [.completed])
        #expect(try store.loadAttachment(by: "a.jpg") == contents)
    }

    @Test("Each file is requested from the bytes already stored")
    func requestsFromStoredOffset() async throws {
        try store.store(attachment: Data(count: 100), filename: "a.jpg.sync.part")
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg"), item("b.jpg")]) }
        let request = try await sentRequest()

        #expect(request.files.map(\.offset) == [100, 0])

        await requester.handle(.header(.init(requestId: request.requestId, fileIndex: 0, totalSize: 100)))
        await requester.handle(.unavailable(.init(requestId: request.requestId, fileIndex: 1, reason: .downloading)))
        await requester.handle(.completed(requestId: request.requestId))

        #expect(await outcomes.value == [.completed, .unavailable(.downloading)])
    }

    @Test("Files without an answer when the request completes are interrupted and keep their bytes")
    func unansweredFilesAreInterrupted() async throws {
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg")]) }
        let request = try await sentRequest()
        await requester.handle(.header(.init(requestId: request.requestId, fileIndex: 0, totalSize: 100)))
        await requester.handle(chunk(request, offset: 0, data: Data(count: 40)))
        await requester.handle(.completed(requestId: request.requestId))

        #expect(await outcomes.value == [.interrupted])
        #expect(store.hasFile(for: "a.jpg.sync.part"))
    }

    @Test("A chunk with a gap fails the file and discards its bytes")
    func gapIsSizeMismatch() async throws {
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg")]) }
        let request = try await sentRequest()
        await requester.handle(.header(.init(requestId: request.requestId, fileIndex: 0, totalSize: 100)))
        await requester.handle(chunk(request, offset: 0, data: Data(count: 10)))
        await requester.handle(chunk(request, offset: 50, data: Data(count: 10)))
        await requester.handle(.completed(requestId: request.requestId))

        #expect(await outcomes.value == [.sizeMismatch])
        #expect(!store.hasFile(for: "a.jpg.sync.part"))
    }

    @Test("Closing the channel interrupts the request and keeps the partial file")
    func closeInterrupts() async throws {
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg")]) }
        let request = try await sentRequest()
        await requester.handle(.header(.init(requestId: request.requestId, fileIndex: 0, totalSize: 100)))
        await requester.handle(chunk(request, offset: 0, data: Data(count: 40)))
        await requester.close()

        #expect(await outcomes.value == [.interrupted])
        #expect(store.hasFile(for: "a.jpg.sync.part"))
        #expect(await requester.request([item("b.jpg")]) == [.interrupted])
    }

    @Test("A provider that never answers makes every file not stored")
    func noResponseTimesOut() async throws {
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg"), item("b.jpg")]) }
        _ = try await sentRequest()
        await sleeper.waitUntilSleeping()
        sleeper.advance()

        #expect(await outcomes.value == [.unavailable(.notStored), .unavailable(.notStored)])
    }

    @Test("The first answer cancels the no-response timeout")
    func answerCancelsTimeout() async throws {
        let requester = makeRequester()

        let outcomes = Task { await requester.request([item("a.jpg")]) }
        let request = try await sentRequest()
        await sleeper.waitUntilSleeping()
        await requester.handle(.unavailable(.init(requestId: request.requestId, fileIndex: 0, reason: .notStored)))

        #expect(await sleeper.waitForOutcome() == .cancelled)

        await requester.handle(.completed(requestId: request.requestId))
        #expect(await outcomes.value == [.unavailable(.notStored)])
    }

    @Test("Request ids are unique for the channel")
    func requestIdsIncrease() async throws {
        let requester = makeRequester()

        let first = Task { await requester.request([item("a.jpg")]) }
        let firstRequest = try await sentRequest()
        await requester.handle(.completed(requestId: firstRequest.requestId))
        _ = await first.value

        let second = Task { await requester.request([item("b.jpg")]) }
        let secondRequest = try await sentRequest(count: 2)
        await requester.handle(.completed(requestId: secondRequest.requestId))
        _ = await second.value

        #expect(secondRequest.requestId == firstRequest.requestId + 1)
    }
}

private extension DeviceSyncFileRequesterTests {
    func makeRequester() -> DeviceSyncFileRequester {
        DeviceSyncFileRequester(
            flow: flow,
            downloadsStore: store,
            sleep: { [sleeper] duration in try await sleeper.sleep(for: duration) },
            logger: Logger.shared
        )
    }

    func item(_ filename: String) -> DeviceSyncFileRequestItem {
        DeviceSyncFileRequestItem(
            file: .messageAttachment(.init(messageId: "message-\(filename)", identifier: Data(filename.utf8))),
            filename: filename
        )
    }

    func sentRequest(count: Int = 1) async throws -> Message.Request {
        let sent = await flow.waitForSentFileMessageCount(count)
        guard case let .filesRequest(request) = sent[count - 1] else {
            Issue.record("Expected a files request, got \(sent[count - 1])")
            throw CancellationError()
        }
        return request
    }

    func chunk(_ request: Message.Request, offset: UInt64, data: Data) -> Message {
        .chunk(.init(requestId: request.requestId, fileIndex: 0, offset: offset, data: data))
    }
}
