import Foundation
import AsyncExtensions

actor DataConnectionContext {
    struct FlushParams {
        let delayInSec: TimeInterval
        let limitPerFlush: Int
    }

    let signaler: PeerConnectionSignaling
    let logger: LoggerProtocol

    nonisolated let sentSignals = AsyncPassthroughSubject<(PeerConnectionSignal, PeerConnectionSignalStateObserving)>()

    private var autoflushParams: FlushParams?

    private var signalsBuffer: [PeerConnectionSignal] = []
    private var flushTask: Task<Void, Never>?

    var signals: AnyAsyncSequence<PeerConnectionSignal> {
        signaler.signals
    }

    init(signaler: PeerConnectionSignaling, logger: LoggerProtocol) {
        self.signaler = signaler
        self.logger = logger
    }

    func append(_ signal: PeerConnectionSignal) {
        signalsBuffer.append(signal)

        guard let autoflushParams else {
            return
        }

        ensureFlushTaskRunning(with: autoflushParams)
    }

    func sendSignalAndFlushBuffer(
        _ signal: PeerConnectionSignal,
        flushDelay: TimeInterval = 0.5,
        limitPerFlush: Int = 4
    ) {
        signalsBuffer.insert(signal, at: 0)

        autoflushParams = nil
        cancelFlushTask()

        ensureFlushTaskRunning(with: FlushParams(delayInSec: flushDelay, limitPerFlush: limitPerFlush))
    }

    func startAutoflush(with delay: TimeInterval = 0.5, limitPerFlush: Int = 4) {
        let params = FlushParams(delayInSec: delay, limitPerFlush: limitPerFlush)
        autoflushParams = params

        guard !signalsBuffer.isEmpty else {
            return
        }

        ensureFlushTaskRunning(with: params)
    }
}

extension DataConnectionContext {
    func ensureFlushTaskRunning(with params: FlushParams) {
        guard flushTask == nil else {
            return
        }

        flushTask = Task { [weak self] in
            do {
                let delay = UInt64(TimeInterval(NSEC_PER_SEC) * params.delayInSec)
                try await Task.sleep(nanoseconds: delay)
                await self?.performFlushBuffer(with: params.limitPerFlush)
            } catch {
                return // cancelled
            }
        }
    }

    func cancelFlushTask() {
        flushTask?.cancel()
        flushTask = nil
    }

    func performFlushBuffer(with limit: Int) async {
        flushTask = nil

        guard !signalsBuffer.isEmpty else {
            return
        }

        let itemsToSend = signalsBuffer.prefix(limit)
        signalsBuffer = Array(signalsBuffer.dropFirst(limit))

        for signal in itemsToSend {
            let observer = try? await signaler.send(signal)
            if let observer {
                sentSignals.send((signal, observer))
            }
        }

        guard !signalsBuffer.isEmpty, let autoflushParams else {
            return
        }

        ensureFlushTaskRunning(with: autoflushParams)
    }
}
