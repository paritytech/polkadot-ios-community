@testable import Coinage
import Foundation
import Testing

@Suite("Stream Consumption")
struct StreamConsumptionTests {
    // MARK: - No Element Loss

    @Test(
        "Elements arriving inside the idle window are delivered in order",
        .timeLimit(.minutes(1))
    )
    func elementsInsideIdleWindowDeliveredInOrder() async throws {
        var seen: [Int] = []

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            continuation.yield(1)
            try await Task.sleep(for: .milliseconds(50))
            continuation.yield(2)
            continuation.finish()
        }

        await consume(stream, idleTimeout: .milliseconds(200)) { element in
            seen.append(element)
            return false
        }

        #expect(seen == [1, 2])
    }

    // MARK: - Idle Timeout Semantics

    @Test(
        "Idle timeout ends consumption when no element arrives",
        .timeLimit(.minutes(1))
    )
    func idleTimeoutEndsConsumption() async throws {
        var seen: [Int] = []
        let idleTimeoutMs = 100
        let idleTimeout: Duration = .milliseconds(idleTimeoutMs)

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            continuation.yield(1)
            // Don't yield anything else; let timeout fire
        }

        let startTime = Date()
        await consume(stream, idleTimeout: idleTimeout) { element in
            seen.append(element)
            return false
        }
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(seen == [1])
        let expectedSeconds = Double(idleTimeoutMs) / 1_000.0
        #expect(elapsed >= expectedSeconds * 0.9)
        #expect(elapsed <= expectedSeconds * 1.5)
    }

    // MARK: - Timeout Reset Per Element

    @Test(
        "Idle timeout is re-armed per element; total duration > timeout is OK",
        .timeLimit(.minutes(1))
    )
    func timeoutResetPerElement() async throws {
        var seen: [Int] = []
        let elementDelayMs = 80
        let elementDelay: Duration = .milliseconds(elementDelayMs)
        let idleTimeout: Duration = .milliseconds(150)
        let elementCount = 5

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            for i in 1 ... elementCount {
                continuation.yield(i)
                if i < elementCount {
                    try await Task.sleep(for: elementDelay)
                }
            }
            continuation.finish()
        }

        let startTime = Date()
        await consume(stream, idleTimeout: idleTimeout) { element in
            seen.append(element)
            return false
        }
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(seen == [1, 2, 3, 4, 5])
        let expectedSeconds = Double(elementDelayMs) / 1_000.0 * Double(elementCount - 1)
        #expect(elapsed >= expectedSeconds * 0.8)
        #expect(elapsed <= expectedSeconds * 1.5)
    }

    // MARK: - Handle Return True Stops Consumption

    @Test(
        "Returning true from handle stops consumption",
        .timeLimit(.minutes(1))
    )
    func handleReturnTrueStops() async throws {
        var seen: [Int] = []

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }

        await consume(stream, idleTimeout: .milliseconds(500)) { element in
            seen.append(element)
            return element == 2 // Stop after seeing 2
        }

        #expect(seen == [1, 2])
    }

    // MARK: - Stream Finish

    @Test(
        "Stream finishing normally ends consumption",
        .timeLimit(.minutes(1))
    )
    func streamFinishEndsConsumption() async throws {
        var seen: [Int] = []

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            for i in 1 ... 3 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        await consume(stream, idleTimeout: .seconds(10)) { element in
            seen.append(element)
            return false
        }

        #expect(seen == [1, 2, 3])
    }

    // MARK: - Complex Scenario

    @Test(
        "Timeout fires in middle of spaced elements",
        .timeLimit(.minutes(1))
    )
    func timeoutFiresOnLongSilence() async throws {
        var seen: [Int] = []
        let idleTimeout: Duration = .milliseconds(150)

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            continuation.yield(1)
            try await Task.sleep(for: .milliseconds(80))
            continuation.yield(2)
            // Now wait longer than idleTimeout before next element
            try await Task.sleep(for: .milliseconds(200))
            continuation.yield(3) // This won't be seen
            continuation.finish()
        }

        let startTime = Date()
        await consume(stream, idleTimeout: idleTimeout) { element in
            seen.append(element)
            return false
        }
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(seen == [1, 2])
        let expectedMs = 80 + 200 // First yield + sleep + second yield + sleep + timeout
        let expectedSeconds = Double(expectedMs) / 1_000.0
        #expect(elapsed >= expectedSeconds * 0.7)
    }

    // MARK: - Defect 1: First Element Idle Timeout

    @Test(
        "First element is covered by idle timeout (stream never yields or finishes)",
        .timeLimit(.minutes(1))
    )
    func firstElementCoveredByIdleTimeout() async throws {
        var seen: [Int] = []
        let idleTimeout: Duration = .milliseconds(100)

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            // Keep the continuation alive by sleeping longer than the timeout.
            // This prevents the stream from finishing early and ensures we test
            // the idle timeout path for the first element.
            _ = continuation
            try await Task.sleep(for: .milliseconds(500))
        }

        let startTime = Date()
        await consume(stream, idleTimeout: idleTimeout) { element in
            seen.append(element)
            return false
        }
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(seen == [])
        let expectedSeconds = Double(100) / 1_000.0
        #expect(elapsed >= expectedSeconds * 0.8)
        #expect(elapsed <= expectedSeconds * 1.5)
    }

    // MARK: - Defect 2: Stale Nil Handling

    @Test(
        "Elements near idle timeout boundary do not cause early termination",
        .timeLimit(.minutes(1))
    )
    func noEarlyTerminationFromStaleNil() async throws {
        // This test exercises the race condition where a watchdog might fire
        // at nearly the same moment as an element arrives, creating a stale nil
        // in the buffer. Elements are spaced at just under the idle timeout to
        // increase the chance of hitting this timing window. The spacing is
        // intentionally tight but timing-dependent; flakiness suggests the
        // defect is present.

        var seen: [Int] = []
        let elementDelayMs = 95
        let elementDelay: Duration = .milliseconds(elementDelayMs)
        let idleTimeout: Duration = .milliseconds(150)
        let elementCount = 5

        let (stream, continuation) = AsyncStream<Int>.makeStream()

        Task {
            for i in 1 ... elementCount {
                continuation.yield(i)
                if i < elementCount {
                    try await Task.sleep(for: elementDelay)
                }
            }
            continuation.finish()
        }

        await consume(stream, idleTimeout: idleTimeout) { element in
            seen.append(element)
            return false
        }

        #expect(seen == [1, 2, 3, 4, 5])
    }
}
