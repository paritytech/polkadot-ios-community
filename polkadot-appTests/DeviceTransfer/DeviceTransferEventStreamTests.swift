@testable import polkadot_app
import Foundation
import StructuredConcurrencyTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferEventStreamTests {
    private let flow = MockDevicePeerConnectionFlow(startResult: .success(()))
    private let clock = ManualClock()
    private let timeout: Duration = .seconds(30)

    @Test("A control that arrives while a wait is pending ends that wait")
    func controlArrivesWhileWaiting() async throws {
        let stream = await openStream()
        let waiting = Task { try await stream.waitForControl { $0 == .receiverCompleted ? () : nil } }

        await clock.waitForSleep(for: timeout)
        await flow.emitTransferControl(.receiverCompleted)

        try await waiting.value
        await stream.close()
    }

    @Test("Nothing within the timeout fails the wait as timed out")
    func silenceTimesOut() async throws {
        let stream = await openStream()
        let waiting = Task { try await stream.next() }

        await clock.resumeSleep(for: timeout)

        await #expect(throws: DeviceTransferRunError.timedOut) { try await waiting.value }
        await stream.close()
    }

    @Test("Each file request restarts the deadline on the serving side")
    func fileRequestsRestartTheDeadline() async throws {
        let stream = await openStream(countsFileRequests: true)
        let waiting = Task { try await stream.waitForControl { $0 == .receiverCompleted ? () : nil } }

        for requestId in 0 ..< 3 {
            await clock.waitForSleepStarts(for: timeout, count: requestId + 1)
            await flow.emitFileMessage(.cancelFilesRequest(requestId: UInt32(requestId)))
        }
        await clock.waitForSleepStarts(for: timeout, count: 4)
        await flow.emitTransferControl(.receiverCompleted)

        try await waiting.value
        await stream.close()
    }

    @Test("Closing the stream or cancelling the waiter ends a pending wait", arguments: [false, true])
    func pendingWaitEnds(byCancelling: Bool) async throws {
        let stream = await openStream()
        let waiting = Task { try await stream.next() }

        await clock.waitForSleep(for: timeout)
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
        let stream = await openStream()
        await flow.emitTransferControl(.abort(.userCancelled))

        await #expect(throws: DeviceTransferRunError.aborted(.userCancelled)) { try await stream.next() }
        await stream.close()
    }
}

private extension DeviceTransferEventStreamTests {
    func openStream(countsFileRequests: Bool = false) async -> DeviceTransferEventStream {
        await DeviceTransferEventStream.open(
            flow: flow,
            timeout: timeout,
            clock: clock,
            countsFileRequests: countsFileRequests
        )
    }
}
