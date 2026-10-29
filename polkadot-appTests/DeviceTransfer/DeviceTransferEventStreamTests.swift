@testable import polkadot_app
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferEventStreamTests {
    private let flow = MockDevicePeerConnectionFlow(startResult: .success(()))

    @Test("A control that arrives while a wait is pending ends that wait")
    func controlArrivesWhileWaiting() async throws {
        let stream = await DeviceTransferEventStream.open(flow: flow, timeout: .seconds(5))
        let waiting = Task { try await stream.waitForControl { $0 == .receiverCompleted ? () : nil } }

        try await Task.sleep(for: .milliseconds(50))
        await flow.emitTransferControl(.receiverCompleted)

        try await waiting.value
        await stream.close()
    }

    @Test("Nothing within the timeout fails the wait as timed out")
    func silenceTimesOut() async throws {
        let stream = await DeviceTransferEventStream.open(flow: flow, timeout: .milliseconds(50))

        await #expect(throws: DeviceTransferRunError.timedOut) { try await stream.next() }
        await stream.close()
    }

    @Test("File requests keep a wait alive past its timeout on the serving side")
    func fileRequestsRestartTheDeadline() async throws {
        let stream = await DeviceTransferEventStream.open(
            flow: flow,
            timeout: .milliseconds(150),
            countsFileRequests: true
        )
        let waiting = Task { try await stream.waitForControl { $0 == .receiverCompleted ? () : nil } }

        for requestId in 0 ..< 4 {
            try await Task.sleep(for: .milliseconds(80))
            await flow.emitFileMessage(.cancelFilesRequest(requestId: UInt32(requestId)))
        }
        await flow.emitTransferControl(.receiverCompleted)

        try await waiting.value
        await stream.close()
    }

    @Test("Closing the stream or cancelling the waiter ends a pending wait", arguments: [false, true])
    func pendingWaitEnds(byCancelling: Bool) async throws {
        let stream = await DeviceTransferEventStream.open(flow: flow, timeout: .seconds(30))
        let waiting = Task { try await stream.next() }

        try await Task.sleep(for: .milliseconds(50))
        if byCancelling {
            waiting.cancel()
        } else {
            await stream.close()
        }

        await #expect(throws: CancellationError.self) { try await waiting.value }
        await stream.close()
    }

    @Test("An abort from the other phone fails the wait")
    func abortFailsWait() async throws {
        let stream = await DeviceTransferEventStream.open(flow: flow, timeout: .seconds(5))
        await flow.emitTransferControl(.abort(.userCancelled))

        await #expect(throws: DeviceTransferRunError.aborted(.userCancelled)) { try await stream.next() }
        await stream.close()
    }
}
