import Foundation
import AsyncExtensions

enum DeviceTransferRunError: Error, Equatable {
    case aborted(DeviceTransferAbortReason)
    case disconnected
    case timedOut
}

enum DeviceTransferEvent {
    case control(DeviceTransferControl)
    case update(Chat.DeviceSyncUpdate)
    case ack(UInt32)
}

/// Merges what a transfer side waits on (controls, updates, acks, channel loss and its own timeout) into one
/// stream, so every wait observes an abort or a disconnect as soon as it happens.
struct DeviceTransferEventStream {
    fileprivate enum Signal {
        case event(DeviceTransferEvent)
        case disconnected
        case timeout(UInt64)
    }

    private let timeout: Duration
    private let sleep: DeviceSyncSleep
    private let continuation: AsyncStream<Signal>.Continuation
    private let forwarders: [Task<Void, Never>]
    private var signals: AsyncStream<Signal>.Iterator
    private var timeoutToken: UInt64 = 0

    init(flow: any DevicePeerConnectionFlowing, timeout: Duration, sleep: @escaping DeviceSyncSleep) async {
        let (stream, continuation) = AsyncStream.makeStream(of: Signal.self)

        self.timeout = timeout
        self.sleep = sleep
        self.continuation = continuation
        signals = stream.makeAsyncIterator()
        forwarders = await Self.startForwarders(flow: flow, into: continuation)
    }

    func close() {
        forwarders.forEach { $0.cancel() }
        continuation.finish()
    }

    /// The next event, failing on an abort, a lost channel, or nothing arriving within the timeout.
    mutating func next(within timeout: Duration? = nil) async throws -> DeviceTransferEvent {
        timeoutToken += 1
        let token = timeoutToken
        let timer = startTimer(token: token, timeout: timeout ?? self.timeout)
        defer { timer.cancel() }

        while let signal = await signals.next() {
            switch signal {
            case let .event(.control(.abort(reason))):
                throw DeviceTransferRunError.aborted(reason)
            case let .event(event):
                return event
            case .disconnected:
                throw DeviceTransferRunError.disconnected
            case let .timeout(firedToken):
                if firedToken == token {
                    throw DeviceTransferRunError.timedOut
                }
            }
        }

        throw CancellationError()
    }

    mutating func waitForControl<Result>(
        within timeout: Duration? = nil,
        _ match: (DeviceTransferControl) -> Result?
    ) async throws -> Result {
        while true {
            if case let .control(control) = try await next(within: timeout), let result = match(control) {
                return result
            }
        }
    }
}

private extension DeviceTransferEventStream {
    static func startForwarders(
        flow: any DevicePeerConnectionFlowing,
        into continuation: AsyncStream<Signal>.Continuation
    ) async -> [Task<Void, Never>] {
        let controls = await flow.transferControls.makeAsyncIterator()
        let updates = await flow.updates.makeAsyncIterator()
        let acks = await flow.acks.makeAsyncIterator()
        let states = await flow.states.makeAsyncIterator()

        return [
            forward(controls, into: continuation) { .event(.control($0)) },
            forward(updates, into: continuation) { .event(.update($0)) },
            forward(acks, into: continuation) { .event(.ack($0.id)) },
            forward(states, into: continuation) { $0 == .disconnected ? .disconnected : nil }
        ]
    }

    static func forward<Element>(
        _ initialIterator: AnyAsyncIterator<Element>,
        into continuation: AsyncStream<Signal>.Continuation,
        transform: @escaping @Sendable (Element) -> Signal?
    ) -> Task<Void, Never> {
        Task {
            var iterator = initialIterator
            while let element = try? await iterator.next() {
                if let signal = transform(element) {
                    continuation.yield(signal)
                }
            }
            guard !Task.isCancelled else { return }
            continuation.yield(.disconnected)
        }
    }

    func startTimer(token: UInt64, timeout: Duration) -> Task<Void, Never> {
        let sleep = sleep
        let continuation = continuation

        return Task {
            guard await (try? sleep(timeout)) != nil, !Task.isCancelled else { return }
            continuation.yield(.timeout(token))
        }
    }
}
