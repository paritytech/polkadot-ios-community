import BigInt
import Foundation
import os
import SubstrateSdk
@testable import Coinage

/// Scripted planner: answers from `handler` when set, else from a FIFO queue, else `defaultResult`.
/// Records every `(amount, mustInclude)` it was asked to plan.
final class StubExternalPaymentPlanner: ExternalPaymentPlanning, @unchecked Sendable {
    struct Failure: LocalizedError, Equatable {
        let message: String

        init(_ message: String = "planner boom") {
            self.message = message
        }

        var errorDescription: String? { message }
    }

    typealias Handler = @Sendable (Balance, [Voucher]) -> Result<ExternalPaymentPreview, Error>

    private struct State {
        var queue: [Result<ExternalPaymentPreview, Error>] = []
        var defaultResult: Result<ExternalPaymentPreview, Error>
        var calls: [(amount: Balance, mustInclude: [Voucher])] = []
        var handler: Handler?
        var blockUntilCancelled = false
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

    func setHandler(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
    }

    /// Every plan call suspends until the surrounding task is cancelled.
    func blockUntilCancelled() {
        state.withLock { $0.blockUntilCancelled = true }
    }

    var calls: [(amount: Balance, mustInclude: [Voucher])] {
        state.withLock { $0.calls }
    }

    var amounts: [Balance] { calls.map(\.amount) }

    func plan(
        amount: Balance,
        context _: DenominationBreakdownContext,
        mustInclude: [Voucher]
    ) async throws -> ExternalPaymentPreview {
        let (result, blocks) = state.withLock { state -> (Result<ExternalPaymentPreview, Error>, Bool) in
            state.calls.append((amount, mustInclude))
            if let handler = state.handler {
                return (handler(amount, mustInclude), state.blockUntilCancelled)
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
