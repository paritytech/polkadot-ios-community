import Foundation
import AsyncExtensions

protocol AccountSearching<RecentPayload, MatchPayload>: AnyObject {
    associatedtype RecentPayload
    associatedtype MatchPayload

    func setup()
    func sourcesChanged() -> AnyAsyncSequence<Void>
    func searchPhases(
        query: String?
    ) -> AsyncThrowingStream<AccountSearchSections<RecentPayload, MatchPayload>, Error>
}

extension AccountSearching {
    /// Drains every phase and reports the final one. A stream that finishes without a phase was
    /// cancelled, and an empty result there would read as "no such account" to the caller.
    func search(query: String?) async throws -> AccountSearchSections<RecentPayload, MatchPayload> {
        var lastPhase: AccountSearchSections<RecentPayload, MatchPayload>?

        for try await phase in searchPhases(query: query) {
            lastPhase = phase
        }

        guard let lastPhase else {
            throw CancellationError()
        }

        return lastPhase
    }
}
