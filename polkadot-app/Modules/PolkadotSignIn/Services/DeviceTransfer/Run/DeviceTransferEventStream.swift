import Foundation
import AsyncExtensions
import StructuredConcurrency

enum DeviceTransferRunError: Error, Equatable {
    case aborted(DeviceTransferAbortReason)
    case disconnected
    case timedOut
}

enum DeviceTransferEvent: Sendable {
    case control(DeviceTransferControl)
    case update(Chat.DeviceSyncUpdate)
    case ack(UInt32)
}

actor DeviceTransferEventStream {
    fileprivate enum Signal: Sendable {
        case event(DeviceTransferEvent)
        case activity
        case disconnected
    }

    private let timeout: Duration
    private let clock: any Clock<Duration>
    private var pending: [Signal] = []
    private var waiter: CheckedContinuation<Signal?, Never>?
    private var forwarders: [Task<Void, Never>] = []
    private var isClosed = false

    private init(timeout: Duration, clock: any Clock<Duration>) {
        self.timeout = timeout
        self.clock = clock
    }

    /// Subscribes to the flow before returning, so nothing it delivers after `start()` is missed.
    /// Only the file-serving side may count file messages: the pulling side would buffer every chunk.
    static func open(
        flow: any DevicePeerConnectionFlowing,
        timeout: Duration,
        clock: any Clock<Duration> = ContinuousClock(),
        countsFileRequests: Bool = false
    ) async -> DeviceTransferEventStream {
        let stream = DeviceTransferEventStream(timeout: timeout, clock: clock)
        await stream.subscribe(to: flow, countsFileRequests: countsFileRequests)
        return stream
    }

    func close() {
        isClosed = true
        forwarders.forEach { $0.cancel() }
        forwarders = []
        resumeWaiter(with: nil)
    }

    func next(within timeout: Duration? = nil) async throws -> DeviceTransferEvent {
        let timeout = timeout ?? self.timeout

        while true {
            switch try await nextSignal(within: timeout) {
            case let .event(.control(.abort(reason))):
                throw DeviceTransferRunError.aborted(reason)
            case let .event(event):
                return event
            case .activity:
                continue
            case .disconnected:
                throw DeviceTransferRunError.disconnected
            }
        }
    }

    func waitForControl<Result: Sendable>(
        within timeout: Duration? = nil,
        _ match: @Sendable (DeviceTransferControl) -> Result?
    ) async throws -> Result {
        while true {
            if case let .control(control) = try await next(within: timeout), let result = match(control) {
                return result
            }
        }
    }
}

private extension DeviceTransferEventStream {
    func subscribe(to flow: any DevicePeerConnectionFlowing, countsFileRequests: Bool) async {
        let controls = await flow.transferControls.makeAsyncIterator()
        let updates = await flow.updates.makeAsyncIterator()
        let acks = await flow.acks.makeAsyncIterator()
        let states = await flow.states.makeAsyncIterator()

        forwarders = [
            forward(controls) { .event(.control($0)) },
            forward(updates) { .event(.update($0)) },
            forward(acks) { .event(.ack($0.id)) },
            forward(states) { $0 == .disconnected ? .disconnected : nil }
        ]

        if countsFileRequests {
            let fileMessages = await flow.fileMessages.makeAsyncIterator()
            forwarders.append(forward(fileMessages) { _ in .activity })
        }
    }

    func forward<Element>(
        _ initialIterator: AnyAsyncIterator<Element>,
        transform: @escaping @Sendable (Element) -> Signal?
    ) -> Task<Void, Never> {
        Task { [weak self] in
            var iterator = initialIterator
            while let element = try? await iterator.next() {
                if let signal = transform(element) {
                    await self?.receive(signal)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.receive(.disconnected)
        }
    }

    func receive(_ signal: Signal) {
        guard !isClosed else { return }

        if waiter != nil {
            resumeWaiter(with: signal)
        } else {
            pending.append(signal)
        }
    }

    func nextSignal(within timeout: Duration) async throws -> Signal {
        let signal: Signal?

        do {
            signal = try await withTimeout(timeout, clock: clock) { [self] in await takeSignal() }
        } catch is TimeoutError {
            throw DeviceTransferRunError.timedOut
        }

        guard let signal else { throw CancellationError() }
        return signal
    }

    /// `nil` once the stream is closed or the waiting task is cancelled.
    func takeSignal() async -> Signal? {
        if !pending.isEmpty {
            return pending.removeFirst()
        }

        guard !isClosed, !Task.isCancelled else { return nil }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter = continuation
            }
        } onCancel: {
            Task { await self.resumeWaiter(with: nil) }
        }
    }

    func resumeWaiter(with signal: Signal?) {
        let waiter = waiter
        self.waiter = nil
        waiter?.resume(returning: signal)
    }
}
