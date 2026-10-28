@testable import polkadot_app
import AsyncExtensions
import Foundation
import FoundationExt
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DeviceTransferCoordinatorTests {
    private let request = DeviceTransferRequest(
        requestId: "request",
        deviceModel: "iPhone 17 Pro",
        operatingSystem: "iOS 26.1",
        createdAt: 1_700_000_000_000
    )
    private let senderInstallationId = Data(repeating: 0x5E, count: 32)
    private let runs = ScriptedRunFactory()
    private let processed = RecordingProcessedStore()

    @Test("A request older than 15 minutes isn't confirmed, marked or run")
    func staleRequestIsNotConfirmed() async throws {
        let coordinator = makeSender(minutesAfterRequest: 16)

        await coordinator.confirm(request)

        #expect(await terminalState(of: coordinator.states) == .failed(.expired))
        #expect(processed.marks.isEmpty)
        #expect(runs.senderRuns.isEmpty)
    }

    @Test("Confirming marks the request accepted and runs it to completion")
    func confirmRunsTransfer() async throws {
        runs.script = RunScript(events: [.channelOpened])
        let coordinator = makeSender(minutesAfterRequest: 1)
        let states = await recordStates(of: coordinator.states)

        await coordinator.confirm(request)

        #expect(await terminalState(of: coordinator.states) == .completed)
        #expect(processed.marks == [ProcessedMark(requestId: "request", outcome: .accepted)])
        #expect(await states.values(until: .completed) == [.idle, .connecting, .transferring, .completed])
    }

    @Test("Rejecting marks the request rejected and tells the new phone")
    func rejectTellsReceiver() async throws {
        await makeSender(minutesAfterRequest: 1).reject(request)

        #expect(processed.marks == [ProcessedMark(requestId: "request", outcome: .rejected)])
        #expect(runs.rejections == ["request"])
    }

    @Test("The new phone goes from waiting through sync and files to finalized")
    func receiverRunsThroughToFinalized() async throws {
        let fileProgress = DeviceTransferFileProgress(receivedBytes: 10, totalBytes: 10)
        runs.script = RunScript(events: [
            .peerFound,
            .channelOpened,
            .progress(.syncing(applied: 2, total: 2)),
            .progress(.files(fileProgress))
        ])
        let finalizer = RecordingFinalizer()
        let coordinator = makeReceiver(finalizer: finalizer)
        let states = await recordStates(of: coordinator.states)

        await coordinator.start(configuration: configuration())

        #expect(await terminalState(of: coordinator.states) == .completed)
        #expect(await states.values(until: .completed) == [
            .idle, .waitingForSender, .connecting, .syncing(applied: 2, total: 2), .files(fileProgress),
            .finalizing, .completed
        ])
        #expect(runs.receiverRuns == [senderInstallationId])
        #expect(finalizer.requests == ["request"])
    }

    @Test("A rejection from the old phone fails the transfer without finalizing")
    func rejectionFailsReceiver() async throws {
        runs.script = RunScript(events: [.peerFound], error: DeviceTransferContextError.rejected)
        let finalizer = RecordingFinalizer()
        let coordinator = makeReceiver(finalizer: finalizer)

        await coordinator.start(configuration: configuration())

        #expect(await terminalState(of: coordinator.states) == .failed(.rejected))
        #expect(finalizer.requests.isEmpty)
    }

    @Test("Cancelling on the new phone aborts the run and withdraws the request")
    func cancelWithdrawsRequest() async throws {
        runs.script = RunScript(events: [], waitsForCancel: true)
        let publisher = RecordingPublisher(request: request)
        let coordinator = makeReceiver(publisher: publisher)

        await coordinator.start(configuration: configuration())
        await runs.waitUntilRunning()
        await coordinator.cancel()

        #expect(await terminalState(of: coordinator.states) == .failed(.cancelled))
        #expect(publisher.cancelledRequestIds == ["request"])
    }
}

private extension DeviceTransferCoordinatorTests {
    func makeSender(minutesAfterRequest minutes: Double) -> DeviceTransferSenderCoordinator {
        let requestedAt = Date(timeIntervalSince1970: TimeInterval(request.createdAt) / 1_000)

        return DeviceTransferSenderCoordinator(
            runFactory: runs,
            processedStore: processed,
            dateProvider: MockDateProvider(now: requestedAt.addingTimeInterval(minutes * 60)),
            logger: MockLogger()
        )
    }

    func makeReceiver(
        publisher: RecordingPublisher? = nil,
        finalizer: RecordingFinalizer = RecordingFinalizer()
    ) -> DeviceTransferReceiverCoordinator {
        let oldPhone = ActiveInstallation(
            installationId: senderInstallationId,
            deviceModel: "iPhone 15",
            operatingSystem: "iOS 26.0",
            activatedAt: 1
        )

        return DeviceTransferReceiverCoordinator(
            publisher: publisher ?? RecordingPublisher(request: request),
            installationObserver: FixedInstallationStatus(status: .inactive(oldPhone)),
            runFactory: runs,
            finalizer: finalizer,
            logger: MockLogger()
        )
    }

    func configuration() -> DeviceTransferDiscoveryConfiguration {
        DeviceTransferDiscoveryConfiguration(
            connection: MockStatementStore(),
            signer: StubStatementSigner(accountId: Data(repeating: 0x0A, count: 32))
        )
    }

    /// Subscribes before returning, so no state the coordinator goes through is missed.
    func recordStates(of states: AnyAsyncSequence<DeviceTransferState>) -> StateRecorder {
        let recorder = StateRecorder()
        let iterator = states.makeAsyncIterator()
        Task {
            var iterator = iterator
            while let state = try await iterator.next() {
                recorder.events.record(state)
            }
        }
        return recorder
    }

    func terminalState(of states: AnyAsyncSequence<DeviceTransferState>) async -> DeviceTransferState? {
        do {
            for try await state in states {
                if case .completed = state { return state }
                if case .failed = state { return state }
            }
        } catch {
            Issue.record("State stream failed: \(error)")
        }
        return nil
    }
}

private final class StateRecorder: Sendable {
    let events = DeviceSyncTestEventRecorder<DeviceTransferState>()

    func values(until terminal: DeviceTransferState) async -> [DeviceTransferState] {
        while events.snapshot.last != terminal {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return events.snapshot
    }
}

private struct RunScript {
    var events: [DeviceTransferRunEvent] = []
    var error: Error?
    var waitsForCancel = false
}

private final class ScriptedRunFactory: DeviceTransferRunMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let runningEvents = DeviceSyncTestEventRecorder<Void>()
    private var _script = RunScript()
    private var _senderRuns: [String] = []
    private var _receiverRuns: [Data] = []
    private var _rejections: [String] = []

    var script: RunScript {
        get { lock.withLock { _script } }
        set { lock.withLock { _script = newValue } }
    }

    var senderRuns: [String] { lock.withLock { _senderRuns } }
    var receiverRuns: [Data] { lock.withLock { _receiverRuns } }
    var rejections: [String] { lock.withLock { _rejections } }

    func makeSenderRun(for request: DeviceTransferRequest) throws -> any DeviceTransferRunning {
        lock.withLock { _senderRuns.append(request.requestId) }
        return ScriptedRun(script: script, running: runningEvents)
    }

    func makeReceiverRun(
        for _: DeviceTransferRequest,
        senderInstallationId: Data
    ) throws -> any DeviceTransferRunning {
        lock.withLock { _receiverRuns.append(senderInstallationId) }
        return ScriptedRun(script: script, running: runningEvents)
    }

    func sendRejection(for request: DeviceTransferRequest) async throws {
        lock.withLock { _rejections.append(request.requestId) }
    }

    func waitUntilRunning() async {
        _ = await runningEvents.waitForCount(1)
    }
}

private actor ScriptedRun: DeviceTransferRunning {
    private let script: RunScript
    private let running: DeviceSyncTestEventRecorder<Void>
    private var cancelContinuation: CheckedContinuation<Void, Never>?
    private var isCancelled = false

    init(script: RunScript, running: DeviceSyncTestEventRecorder<Void>) {
        self.script = script
        self.running = running
    }

    func run(onEvent: @escaping DeviceTransferRunEventHandler) async throws {
        script.events.forEach(onEvent)

        if script.waitsForCancel {
            await withCheckedContinuation { continuation in
                cancelContinuation = continuation
                running.record(())
            }
            throw CancellationError()
        }

        running.record(())
        if let error = script.error { throw error }
    }

    func cancel() {
        cancelContinuation?.resume()
        cancelContinuation = nil
    }
}

private struct ProcessedMark: Equatable {
    let requestId: String
    let outcome: DeviceTransferOutcome
}

private final class RecordingProcessedStore: DeviceTransferProcessedStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _marks: [ProcessedMark] = []

    var marks: [ProcessedMark] { lock.withLock { _marks } }

    func markProcessed(requestId: String, outcome: DeviceTransferOutcome) async throws {
        lock.withLock { _marks.append(ProcessedMark(requestId: requestId, outcome: outcome)) }
    }

    func processedRequestIds(among _: [String]) async throws -> Set<String> { [] }
}

private final class RecordingPublisher: DeviceTransferRequestPublishing, @unchecked Sendable {
    private let request: DeviceTransferRequest
    private let lock = NSLock()
    private var _cancelledRequestIds: [String] = []

    var cancelledRequestIds: [String] { lock.withLock { _cancelledRequestIds } }

    init(request: DeviceTransferRequest) {
        self.request = request
    }

    func publishRequest(configuration _: DeviceTransferDiscoveryConfiguration) async throws -> DeviceTransferRequest {
        request
    }

    func cancel(requestId: String, configuration _: DeviceTransferDiscoveryConfiguration) async throws {
        lock.withLock { _cancelledRequestIds.append(requestId) }
    }
}

private final class RecordingFinalizer: DeviceTransferFinalizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []

    var requests: [String] { lock.withLock { _requests } }

    func finalize(after request: DeviceTransferRequest) async throws {
        lock.withLock { _requests.append(request.requestId) }
    }
}

private struct FixedInstallationStatus: CurrentInstallationObserving {
    let status: InstallationStatus

    var statusStream: AnyAsyncSequence<InstallationStatus> {
        AsyncCurrentValueSubject<InstallationStatus>(status).eraseToAnyAsyncSequence()
    }
}
