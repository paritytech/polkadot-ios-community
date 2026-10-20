@testable import polkadot_app
import Foundation
import Testing

struct SiblingFileFetcherTests {
    @Test("Without an open sibling channel every file is not stored right away")
    func noChannelIsNotStored() async {
        let fetcher = SiblingFileFetcher(channels: DeviceSyncFileChannelRegistry())

        let outcomes = await fetcher.fetch(makeItems(count: 2))

        #expect(outcomes == [.unavailable(.notStored), .unavailable(.notStored)])
    }

    @Test("Files go to the most recently opened channel, at most 64 per request")
    func batchesOnLatestChannel() async {
        let registry = DeviceSyncFileChannelRegistry()
        let older = MockDeviceSyncFileRequester(outcome: .interrupted)
        let latest = MockDeviceSyncFileRequester(outcome: .completed)
        await registry.register(older, connectionId: UUID())
        await registry.register(latest, connectionId: UUID())
        let items = makeItems(count: 65)

        let outcomes = await SiblingFileFetcher(channels: registry).fetch(items)

        #expect(outcomes == Array(repeating: .completed, count: 65))
        #expect(await latest.requests.map(\.count) == [64, 1])
        #expect(await latest.requests.flatMap { $0 } == items)
        #expect(await older.requests.isEmpty)
    }
}

private extension SiblingFileFetcherTests {
    func makeItems(count: Int) -> [DeviceSyncFileRequestItem] {
        (0 ..< count).map { index in
            DeviceSyncFileRequestItem(
                file: .messageAttachment(.init(messageId: "message-\(index)", identifier: Data([UInt8(index)]))),
                filename: "file-\(index)"
            )
        }
    }
}
