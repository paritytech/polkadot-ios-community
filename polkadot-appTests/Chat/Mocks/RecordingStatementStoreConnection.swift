import AsyncExtensions
import Foundation
import os
import StatementStore
import SubstrateSdk

final class RecordingStatementStoreConnection: StatementStoreConnecting, @unchecked Sendable {
    private struct State {
        var submitCount = 0
        var submittedSenders: [Data?] = []
        var fetchCount = 0
        var failures: [Error]
    }

    private let state: OSAllocatedUnfairLock<State>
    private let stored: [Data]
    private let fetchFailure: Error?

    var submitCount: Int { state.withLock { $0.submitCount } }
    var submittedSenders: [Data?] { state.withLock { $0.submittedSenders } }
    var fetchCount: Int { state.withLock { $0.fetchCount } }

    /// Each submit fails with the next queued error, then succeeds.
    init(failures: [Error] = [], stored: [Data] = [], fetchFailure: Error? = nil) {
        state = OSAllocatedUnfairLock(uncheckedState: State(failures: failures))
        self.stored = stored
        self.fetchFailure = fetchFailure
    }

    func submitStatement(with builder: StatementSubmitParametersBuilding) async throws {
        let parameters = try builder.build()
        let sender = try Statement(scaleDecoder: ScaleDecoder(data: parameters.encodedStatement)).getSenderAccountId()

        let failure: Error? = state.withLock { state in
            state.submitCount += 1
            state.submittedSenders.append(sender)
            return state.failures.isEmpty ? nil : state.failures.removeFirst()
        }

        if let failure {
            throw failure
        }
    }

    func fetchStatements(with _: TopicFilter) async throws -> [Data] {
        state.withLock { $0.fetchCount += 1 }

        if let fetchFailure {
            throw fetchFailure
        }

        return stored
    }

    func subscribeStatements(with _: TopicFilter) -> AnyAsyncSequence<StatementsPage> {
        AsyncThrowingStream<StatementsPage, Error> { $0.finish() }.eraseToAnyAsyncSequence()
    }
}
