import Foundation

final class SearchRunner {
    enum State<SearchResult> {
        case started
        case waiting
        case result(SearchResult)
    }

    private enum Constants {
        static let debounceDelay: Duration = .milliseconds(300)
        static let waitingDelay: Duration = .milliseconds(500)
        static let minLoaderDuration: Duration = .milliseconds(500)
    }

    func run<SearchResult>(
        _ operation: @escaping () async -> SearchResult?
    ) -> AsyncStream<State<SearchResult>> {
        AsyncStream { continuation in
            let loaderShownAt = ContinuousClock.now + Constants.debounceDelay + Constants.waitingDelay

            let loaderTask = Task {
                try? await Task.sleep(until: loaderShownAt, clock: .continuous)
                guard !Task.isCancelled else { return }
                continuation.yield(.waiting)
            }

            let searchTask = Task {
                continuation.yield(.started)

                try? await Task.sleep(for: Constants.debounceDelay)
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                let result = await operation()
                loaderTask.cancel()

                // Keep a loader that already appeared on screen long enough to read.
                if ContinuousClock.now >= loaderShownAt {
                    try? await Task.sleep(
                        until: loaderShownAt + Constants.minLoaderDuration,
                        clock: .continuous
                    )
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                if let result {
                    continuation.yield(.result(result))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                loaderTask.cancel()
                searchTask.cancel()
            }
        }
    }
}
