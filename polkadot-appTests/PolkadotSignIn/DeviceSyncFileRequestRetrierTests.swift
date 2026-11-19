@testable import polkadot_app
import Foundation
import Testing

struct DeviceSyncFileRequestRetrierTests {
    private let retrier = DeviceSyncFileRequestRetrier(extraAttempts: 2)
    private let items = (0 ..< 3).map { index in
        DeviceSyncFileRequestItem(
            file: .messageAttachment(.init(messageId: "message-\(index)", identifier: Data([UInt8(index)]))),
            filename: "file-\(index)"
        )
    }

    @Test("Mismatching files are re-requested until they complete, keeping the input order")
    func retriesUntilCompleted() async {
        let requester = MockDeviceSyncFileRequester(scriptedOutcomes: [
            [.completed, .hashMismatch, .hashMismatch],
            [.hashMismatch, .completed],
            [.completed]
        ])

        let outcomes = await retrier.request(items, using: requester, onBytes: { _ in })

        #expect(outcomes == [.completed, .completed, .completed])
        #expect(await requester.requests == [items, [items[1], items[2]], [items[1]]])
    }

    @Test("A file that still mismatches after the extra attempts stays a hash mismatch")
    func givesUpAfterExtraAttempts() async {
        let requester = MockDeviceSyncFileRequester(outcome: .hashMismatch)

        let outcomes = await retrier.request([items[0]], using: requester, onBytes: { _ in })

        #expect(outcomes == [.hashMismatch])
        #expect(await requester.requests.count == 3)
    }

    @Test("Other outcomes are not retried")
    func otherOutcomesAreFinal() async {
        let requester = MockDeviceSyncFileRequester(scriptedOutcomes: [
            [.sizeMismatch, .unavailable(.notStored), .interrupted]
        ])

        let outcomes = await retrier.request(items, using: requester, onBytes: { _ in })

        #expect(outcomes == [.sizeMismatch, .unavailable(.notStored), .interrupted])
        #expect(await requester.requests.count == 1)
    }
}
