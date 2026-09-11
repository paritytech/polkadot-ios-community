import SubstrateSdk
import BigInt
import Foundation
import os
@testable import Coinage

/// Scripted planner: answers from a FIFO queue of results, then falls back to `defaultResult`.
/// Records every `(amount, scope)` it was asked to plan.
final class StubExternalPaymentPlanner: ExternalPaymentPlanning, @unchecked Sendable {
    struct Failure: LocalizedError, Equatable {
        let message: String

        init(_ message: String = "planner boom") {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    private struct State {
        var queue: [Result<ExternalPaymentPreview, Error>] = []
        var defaultResult: Result<ExternalPaymentPreview, Error>
        var calls: [(amount: Balance, scope: SpendScope)] = []
        var blockUntilCancelled = false
        var handler: (@Sendable (Balance, SpendScope) -> Result<ExternalPaymentPreview, Error>)?
    }

    private let state: OSAllocatedUnfairLock<State>

    init(defaultResult: Result<ExternalPaymentPreview, Error> = .success(.notEnoughBalance)) {
        state = OSAllocatedUnfairLock(initialState: State(defaultResult: defaultResult))
    }

    func script(_ results: [Result<ExternalPaymentPreview, Error>]) {
        state.withLock { $0.queue.append(contentsOf: results) }
    }

    func setDefault(_ result: Result<ExternalPaymentPreview, Error>) {
        state.withLock { $0.defaultResult = result }
    }

    /// Answers every call from `handler` (takes precedence over the queue and default).
    func setHandler(_ handler: @escaping @Sendable (Balance, SpendScope) -> Result<ExternalPaymentPreview, Error>) {
        state.withLock { $0.handler = handler }
    }

    /// Every plan call suspends until the surrounding task is cancelled.
    func blockUntilCancelled() {
        state.withLock { $0.blockUntilCancelled = true }
    }

    var calls: [(amount: Balance, scope: SpendScope)] {
        state.withLock { $0.calls }
    }

    var scopes: [SpendScope] { calls.map(\.scope) }
    var amounts: [Balance] { calls.map(\.amount) }

    func plan(
        amount: Balance,
        context _: DenominationBreakdownContext,
        scope: SpendScope
    ) async throws -> ExternalPaymentPreview {
        let (result, blocks) = state.withLock { state -> (Result<ExternalPaymentPreview, Error>, Bool) in
            state.calls.append((amount, scope))
            if let handler = state.handler {
                return (handler(amount, scope), state.blockUntilCancelled)
            }
            let next = state.queue.isEmpty ? state.defaultResult : state.queue.removeFirst()
            return (next, state.blockUntilCancelled)
        }

        if blocks {
            try await Task.sleep(for: .seconds(60))
        }

        return try result.get()
    }
}
