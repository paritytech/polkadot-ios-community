import Foundation

private enum ConsumeSignal<Element: Sendable> {
    case element(Element)
    case sourceEnded
    case idleFired
}

/// Consumes `stream` until it ends, `handle` returns true, or no element arrives within
/// `idleTimeout` of the previous one.
///
/// The stream has a single consumer for the whole call wrapped in a timeout guardian
/// stream. This ensures no element is lost if a timeout fires, unlike passing an iterator
/// to a task and cancelling it mid-operation.
func consume<Element: Sendable>(
    _ stream: AsyncStream<Element>,
    idleTimeout: Duration,
    handle: (Element) async -> Bool
) async {
    let (timedStream, continuation) = AsyncStream<ConsumeSignal<Element>>.makeStream()

    let sourceTask = Task {
        for await element in stream {
            continuation.yield(.element(element))
        }
        continuation.yield(.sourceEnded)
    }

    var watchdog: Task<Void, Never>?
    var lastElementTime = ContinuousClock.now

    defer {
        sourceTask.cancel()
        watchdog?.cancel()
    }

    // Arm watchdog before entering the loop to cover the initial wait for the first element
    watchdog = Task {
        try? await Task.sleep(for: idleTimeout)
        if !Task.isCancelled {
            continuation.yield(.idleFired)
        }
    }

    for await signal in timedStream {
        watchdog?.cancel()

        switch signal {
        case .sourceEnded:
            // Source stream ended; return immediately without elapsed check
            return

        case .idleFired:
            // Validate that the idle timeout has genuinely elapsed, not a stale watchdog
            // that raced with an element arrival
            let elapsed = ContinuousClock.now - lastElementTime
            if elapsed >= idleTimeout {
                return
            }
            // Stale watchdog; re-arm for the remaining window and continue
            watchdog = Task {
                let remainingWindow = idleTimeout - elapsed
                try? await Task.sleep(for: remainingWindow)
                if !Task.isCancelled {
                    continuation.yield(.idleFired)
                }
            }
            continue

        case let .element(element):
            let shouldStop = await handle(element)
            if shouldStop { return }

            lastElementTime = ContinuousClock.now

            // Re-arm watchdog with fresh timeout
            watchdog = Task {
                try? await Task.sleep(for: idleTimeout)
                if !Task.isCancelled {
                    continuation.yield(.idleFired)
                }
            }
        }
    }
}
