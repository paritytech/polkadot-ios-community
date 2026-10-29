@testable import polkadot_app
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferWithFilesClientTests {
    @Test("Files are served only while the inner client runs, whether it completes or fails", arguments: [false, true])
    func fileTransferSpansInnerRun(innerFails: Bool) async throws {
        let files = MockDeviceSyncFileTransferFactory()
        let inner = RecordingClient(files: files, fails: innerFails)
        let client = DeviceTransferWithFilesClient(
            inner: inner,
            fileTransfer: files.makeTransfer(
                flow: MockDevicePeerConnectionFlow(startResult: .success(())),
                peerLogger: MockLogger()
            )
        )

        var didFail = false
        do {
            try await client.run { _ in }
        } catch {
            didFail = true
        }

        #expect(didFail == innerFails)
        #expect(inner.eventsDuringRun.snapshot == [[.started(1)]])
        #expect(files.events.snapshot == [.started(1), .closed(1)])
    }
}

private struct RecordingClient: DeviceTransferClientProtocol {
    let files: MockDeviceSyncFileTransferFactory
    let fails: Bool
    let eventsDuringRun = DeviceSyncTestEventRecorder<[MockDeviceSyncFileTransferFactory.Event]>()

    func run(onEvent _: @escaping DeviceTransferRunEventHandler) async throws {
        eventsDuringRun.record(files.events.snapshot)
        if fails { throw DeviceTransferRunError.disconnected }
    }
}
