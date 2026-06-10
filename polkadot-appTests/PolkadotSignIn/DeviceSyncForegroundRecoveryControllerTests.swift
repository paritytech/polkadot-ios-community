@testable import polkadot_app
import Foundation
import StructuredConcurrency
import Testing

struct DeviceSyncForegroundRecoveryControllerTests {
    @Test("Foreground events run recovery after previous recovery finishes")
    func foregroundEventsRunRecoveryAfterPreviousRecoveryFinishes() async throws {
        let foregroundEvents = ForegroundEventEmitter()
        let controller = DeviceSyncForegroundRecoveryController(
            foregroundEventStreamFactory: { foregroundEvents.stream() },
            logger: MockLogger()
        )
        let recorder = ForegroundRecoveryRecorder()

        await controller.start {
            recorder.startRecovery()
            await recorder.waitUntilReleased()
            recorder.finishRecovery()
        }

        foregroundEvents.emit()
        try await recorder.waitForRecoveryCount(1)

        recorder.releaseOneRecovery()
        try await recorder.waitForFinishCount(1)

        foregroundEvents.emit()
        try await recorder.waitForRecoveryCount(2)

        recorder.releaseOneRecovery()
        try await recorder.waitForFinishCount(2)

        await controller.stop()
    }

    @Test("Stop cancels recovery in progress")
    func stopCancelsRecoveryInProgress() async throws {
        let foregroundEvents = ForegroundEventEmitter()
        let controller = DeviceSyncForegroundRecoveryController(
            foregroundEventStreamFactory: { foregroundEvents.stream() },
            logger: MockLogger()
        )
        let recorder = ForegroundRecoveryRecorder()

        await controller.start {
            recorder.startRecovery()

            await withTaskCancellationHandler {
                await recorder.waitUntilReleased()
            } onCancel: {
                Task {
                    recorder.cancelRecovery()
                }
            }
        }

        foregroundEvents.emit()
        try await recorder.waitForRecoveryCount(1)

        await controller.stop()
        try await recorder.waitForCancellationCount(1)
        recorder.releaseOneRecovery()
    }
}

private final class ForegroundEventEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Void>.Continuation?

    func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation = continuation
            }
        }
    }

    func emit() {
        lock.withLock { continuation }?.yield()
    }
}

private final class ForegroundRecoveryRecorder: @unchecked Sendable {
    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()

    private var recoveryCount = 0
    private var finishCount = 0
    private var cancellationCount = 0

    private var recoveryWaiters = [CountWaiter]()
    private var finishWaiters = [CountWaiter]()
    private var cancellationWaiters = [CountWaiter]()
    private var releaseWaiters = [CheckedContinuation<Void, Never>]()
    private var pendingReleaseCount = 0

    func startRecovery() {
        let readyWaiters = lock.withLock {
            recoveryCount += 1
            return takeReadyWaiters(&recoveryWaiters, currentCount: recoveryCount)
        }

        readyWaiters.forEach { $0.resume() }
    }

    func finishRecovery() {
        let readyWaiters = lock.withLock {
            finishCount += 1
            return takeReadyWaiters(&finishWaiters, currentCount: finishCount)
        }

        readyWaiters.forEach { $0.resume() }
    }

    func cancelRecovery() {
        let readyWaiters = lock.withLock {
            cancellationCount += 1
            return takeReadyWaiters(&cancellationWaiters, currentCount: cancellationCount)
        }

        readyWaiters.forEach { $0.resume() }
    }

    func releaseOneRecovery() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !releaseWaiters.isEmpty else {
                pendingReleaseCount += 1
                return nil
            }

            return releaseWaiters.removeFirst()
        }

        waiter?.resume()
    }

    func waitUntilReleased() async {
        await withCheckedContinuation { continuation in
            let shouldResume = self.lock.withLock {
                guard pendingReleaseCount == 0 else {
                    pendingReleaseCount -= 1
                    return true
                }

                releaseWaiters.append(continuation)
                return false
            }

            if shouldResume {
                continuation.resume()
            }
        }
    }

    func waitForRecoveryCount(_ expectedCount: Int) async throws {
        try await withTimeout(.seconds(10)) {
            await withCheckedContinuation { continuation in
                let shouldResume = self.lock.withLock {
                    guard self.recoveryCount < expectedCount else { return true }

                    self.recoveryWaiters.append(
                        CountWaiter(expectedCount: expectedCount, continuation: continuation)
                    )

                    return false
                }

                if shouldResume {
                    continuation.resume()
                }
            }
        }
    }

    func waitForFinishCount(_ expectedCount: Int) async throws {
        try await withTimeout(.seconds(10)) {
            await withCheckedContinuation { continuation in
                let shouldResume = self.lock.withLock {
                    guard self.finishCount < expectedCount else { return true }

                    self.finishWaiters.append(
                        CountWaiter(expectedCount: expectedCount, continuation: continuation)
                    )

                    return false
                }

                if shouldResume {
                    continuation.resume()
                }
            }
        }
    }

    func waitForCancellationCount(_ expectedCount: Int) async throws {
        try await withTimeout(.seconds(10)) {
            await withCheckedContinuation { continuation in
                let shouldResume = self.lock.withLock {
                    guard self.cancellationCount < expectedCount else { return true }

                    self.cancellationWaiters.append(
                        CountWaiter(expectedCount: expectedCount, continuation: continuation)
                    )

                    return false
                }

                if shouldResume {
                    continuation.resume()
                }
            }
        }
    }

    private func takeReadyWaiters(
        _ waiters: inout [CountWaiter],
        currentCount: Int
    ) -> [CheckedContinuation<Void, Never>] {
        var ready = [CheckedContinuation<Void, Never>]()
        var remaining = [CountWaiter]()

        for waiter in waiters {
            if currentCount >= waiter.expectedCount {
                ready.append(waiter.continuation)
            } else {
                remaining.append(waiter)
            }
        }

        waiters = remaining
        return ready
    }
}
