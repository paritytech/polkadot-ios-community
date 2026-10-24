@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

@Suite(.timeLimit(.minutes(1)))
final class DeviceSyncFileTransferTests {
    typealias Message = Chat.DeviceSyncFileMessage

    private let directory: URL
    private let store: AttachmentStore
    private let flow = MockDeviceSyncPeerConnectionFlow(startResult: .success(()))
    private let registry = DeviceSyncFileChannelRegistry()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSyncFileTransferTests-\(UUID().uuidString)", isDirectory: true)
        store = AttachmentStore(baseDirectory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("A sibling's request is served by this side's provider")
    func incomingRequestIsServed() async throws {
        let file = Message.FileReference.messageAttachment(.init(messageId: "m", identifier: Data([1])))
        let url = try store.store(attachment: Data([1, 2, 3]), filename: "served")
        let transfer = makeTransfer(locations: [file: .stored(url: url, size: 3)])

        await transfer.start()
        await flow.emitFileMessage(.filesRequest(.init(requestId: 4, files: [.init(file: file, offset: 0)])))
        let sent = await flow.waitForSentFileMessageCount(3)

        #expect(sent == [
            .header(.init(requestId: 4, fileIndex: 0, totalSize: 3)),
            .chunk(.init(requestId: 4, fileIndex: 0, offset: 0, data: Data([1, 2, 3]))),
            .completed(requestId: 4)
        ])
    }

    @Test("The open channel's requester gets the sibling's answers until the transfer closes")
    func requesterIsRegisteredWhileOpen() async throws {
        let transfer = makeTransfer(locations: [:])
        await transfer.start()
        let requester = try #require(await registry.openRequester())

        let item = DeviceSyncFileRequestItem(
            file: .messageAttachment(.init(messageId: "m", identifier: Data([2]))),
            filename: "wanted"
        )
        let outcomes = Task { await requester.request([item]) }
        _ = await flow.waitForSentFileMessageCount(1)
        await flow.emitFileMessage(.unavailable(.init(requestId: 0, fileIndex: 0, reason: .downloading)))
        await flow.emitFileMessage(.completed(requestId: 0))

        #expect(await outcomes.value == [.unavailable(.downloading)])

        await transfer.close()
        #expect(await registry.openRequester() == nil)
    }

    @Test("Closing the transfer interrupts requests still waiting for the sibling")
    func closeInterruptsPendingRequests() async throws {
        let transfer = makeTransfer(locations: [:])
        await transfer.start()
        let requester = try #require(await registry.openRequester())
        let item = DeviceSyncFileRequestItem(
            file: .messageAttachment(.init(messageId: "m", identifier: Data([3]))),
            filename: "pending"
        )

        let outcomes = Task { await requester.request([item]) }
        _ = await flow.waitForSentFileMessageCount(1)
        await transfer.close()

        #expect(await outcomes.value == [.interrupted])
    }
}

private extension DeviceSyncFileTransferTests {
    func makeTransfer(locations: [Message.FileReference: DeviceSyncFileLocation]) -> DeviceSyncFileTransfer {
        DeviceSyncFileTransfer(
            flow: flow,
            provider: DeviceSyncFileProvider(
                flow: flow,
                locator: MockDeviceSyncFileLocator(locations: locations),
                logger: Logger.shared
            ),
            requester: DeviceSyncFileRequester(flow: flow, downloadsStore: store, logger: Logger.shared),
            registry: registry,
            peerLogger: Logger.shared
        )
    }
}
