import Foundation

/// Lets a test await a condition on a double's state without polling: the double calls `signal()` after
/// every change, and `wait(until:)` re-checks the condition on each signal. Signals are buffered, so a change
/// made before the wait starts is not missed. One waiter at a time.
final class StateChangeSignal: @unchecked Sendable {
    private let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (changes, continuation) = AsyncStream.makeStream()
    }

    func signal() {
        continuation.yield()
    }

    @MainActor
    func wait(until condition: () -> Bool) async {
        guard !condition() else { return }

        for await _ in changes where condition() {
            return
        }
    }
}
