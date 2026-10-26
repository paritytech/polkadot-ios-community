import Foundation
import AsyncExtensions

enum DeviceTransferRunError: Error, Equatable {
    case aborted(DeviceTransferAbortReason)
    case disconnected
    case timedOut
}

struct DeviceTransferSenderSettings {
    var messagePageSize = 200
    var responseTimeout: Duration = .seconds(30)
    var entityChunker = DeviceSyncEntityChunker()
    var sleep: DeviceSyncSleep = liveDeviceSyncSleep
}

/// Merges what the sender waits on (controls, acks, channel loss and its own timeouts) into one stream,
/// so every wait observes an abort or a disconnect as soon as it happens.
struct DeviceTransferSenderChannel {
    fileprivate enum Event {
        case control(DeviceTransferControl)
        case ack(UInt32)
        case disconnected
        case timeout(UInt64)
    }

    private let flow: any DevicePeerConnectionFlowing
    private let updateIdProvider: DeviceSyncUpdateIdProviding
    private let settings: DeviceTransferSenderSettings
    private let continuation: AsyncStream<Event>.Continuation
    private let forwarders: [Task<Void, Never>]
    private var events: AsyncStream<Event>.Iterator
    private var timeoutToken: UInt64 = 0

    init(
        flow: any DevicePeerConnectionFlowing,
        updateIdProvider: DeviceSyncUpdateIdProviding,
        settings: DeviceTransferSenderSettings
    ) async {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

        self.flow = flow
        self.updateIdProvider = updateIdProvider
        self.settings = settings
        self.continuation = continuation
        events = stream.makeAsyncIterator()
        forwarders = await Self.startForwarders(flow: flow, into: continuation)
    }

    func close() {
        forwarders.forEach { $0.cancel() }
        continuation.finish()
    }

    mutating func waitForResume() async throws -> UInt64? {
        try await waitForControl { control in
            guard case let .resume(timePoint) = control else { return nil }
            return .some(timePoint)
        }
    }

    mutating func waitForReceiverCompleted() async throws {
        try await waitForControl { $0 == .receiverCompleted ? () : nil }
    }

    /// Sends the entities as one or more updates and returns once the receiver has acknowledged all of them.
    /// Empty entities still produce one update, which carries a round's closing time point.
    mutating func deliver(_ entities: [Chat.DeviceSyncEntity], timePoint: UInt64) async throws {
        let batches = entities.isEmpty ? [[]] : try settings.entityChunker.chunk(entities)
        var pendingIds = Set<UInt32>()

        for batch in batches {
            let update = Chat.DeviceSyncUpdate(id: updateIdProvider.nextId(), entities: batch, timePoint: timePoint)
            try await flow.sendUpdate(update)
            pendingIds.insert(update.id)
        }

        try await waitUntil { event in
            if case let .ack(id) = event {
                pendingIds.remove(id)
            }
            return pendingIds.isEmpty ? () : nil
        }
    }
}

private extension DeviceTransferSenderChannel {
    static func startForwarders(
        flow: any DevicePeerConnectionFlowing,
        into continuation: AsyncStream<Event>.Continuation
    ) async -> [Task<Void, Never>] {
        let controls = await flow.transferControls.makeAsyncIterator()
        let acks = await flow.acks.makeAsyncIterator()
        let states = await flow.states.makeAsyncIterator()

        return [
            forward(controls, into: continuation) { .control($0) },
            forward(acks, into: continuation) { .ack($0.id) },
            forward(states, into: continuation) { $0 == .disconnected ? .disconnected : nil }
        ]
    }

    static func forward<Element>(
        _ initialIterator: AnyAsyncIterator<Element>,
        into continuation: AsyncStream<Event>.Continuation,
        transform: @escaping @Sendable (Element) -> Event?
    ) -> Task<Void, Never> {
        Task {
            var iterator = initialIterator
            while let element = try? await iterator.next() {
                if let event = transform(element) {
                    continuation.yield(event)
                }
            }
            guard !Task.isCancelled else { return }
            continuation.yield(.disconnected)
        }
    }

    mutating func waitForControl<Result>(
        _ match: @escaping (DeviceTransferControl) -> Result?
    ) async throws -> Result {
        try await waitUntil { event in
            guard case let .control(control) = event else { return nil }
            return match(control)
        }
    }

    mutating func waitUntil<Result>(_ match: (Event) -> Result?) async throws -> Result {
        timeoutToken += 1
        let token = timeoutToken
        let timer = startTimer(token: token)
        defer { timer.cancel() }

        while let event = await events.next() {
            switch event {
            case let .control(.abort(reason)):
                throw DeviceTransferRunError.aborted(reason)
            case .disconnected:
                throw DeviceTransferRunError.disconnected
            case let .timeout(firedToken):
                if firedToken == token {
                    throw DeviceTransferRunError.timedOut
                }
            case .control,
                 .ack:
                if let result = match(event) {
                    return result
                }
            }
        }

        throw CancellationError()
    }

    func startTimer(token: UInt64) -> Task<Void, Never> {
        let timeout = settings.responseTimeout
        let sleep = settings.sleep
        let continuation = continuation

        return Task {
            guard await (try? sleep(timeout)) != nil, !Task.isCancelled else { return }
            continuation.yield(.timeout(token))
        }
    }
}
