@testable import polkadot_app
import Foundation
import SubstrateSdk
import Operation_iOS
import MessageExchangeKit
import StatementStore
import AsyncExtensions
import StructuredConcurrency

final class MockStatementStore {
    class Observer {
        let filter: TopicFilter
        let continuation: AsyncThrowingStream<[Data], Error>.Continuation

        init(filter: TopicFilter, continuation: AsyncThrowingStream<[Data], Error>.Continuation) {
            self.filter = filter
            self.continuation = continuation
        }
    }

    private var statements = Set<MockStatement>()
    private var observers: [Observer] = []
    private let mutex = NSLock()
    private let replacesByChannel: Bool

    /// - Parameter replacesByChannel: apply the store's rule that a statement replaces the same signer's statement
    ///   on the same channel when its expiry is higher, and is rejected otherwise.
    init(replacesByChannel: Bool = false) {
        self.replacesByChannel = replacesByChannel
    }

    func allStatements() throws -> [Statement] {
        mutex.lock()
        defer { mutex.unlock() }

        return try statements.map { try Statement(scaleDecoder: ScaleDecoder(data: $0.data)) }
    }

    func getStatements(with filter: TopicFilter) throws -> [Data] {
        mutex.lock()
        defer { mutex.unlock() }

        return statements
            .filter { filter.matches(topics: $0.topics) }
            .map(\.data)
    }

    func senderAccountIds() throws -> [AccountId] {
        mutex.lock()
        defer { mutex.unlock() }

        return try statements.compactMap { mockStatement in
            try Statement(scaleDecoder: ScaleDecoder(data: mockStatement.data)).getSenderAccountId()
        }
    }

    func insertStatement(with builder: StatementSubmitParametersBuilding) throws {
        mutex.lock()
        defer { mutex.unlock() }

        let params = try builder.build()

        let statement = try MockStatement(encodedStatement: params.encodedStatement)

        if replacesByChannel {
            try replaceChannelStatement(with: statement)
        }

        statements.insert(statement)

        for observer in observers where observer.filter.matches(topics: statement.topics) {
            observer.continuation.yield([statement.data])
        }
    }

    func addObserver(_ observer: Observer) {
        mutex.lock()
        defer { mutex.unlock() }

        observers.append(observer)

        let matchingStatements = statements
            .filter { observer.filter.matches(topics: $0.topics) }
            .map(\.data)

        observer.continuation.yield(matchingStatements)
    }

    func removeObserver(_ observer: Observer) {
        mutex.lock()
        defer { mutex.unlock() }

        observers = observers.filter { $0 !== observer }
    }

    func failSubscriptions(with error: Error) {
        takeObservers().forEach { $0.continuation.finish(throwing: error) }
    }

    func endSubscriptions() {
        takeObservers().forEach { $0.continuation.finish() }
    }

    private func replaceChannelStatement(with newStatement: MockStatement) throws {
        let decoded = try Statement(scaleDecoder: ScaleDecoder(data: newStatement.data))

        guard let channel = decoded.getChannel(), let sender = decoded.getSenderAccountId() else {
            return
        }

        let replaced = try statements.first { existing in
            let existingStatement = try Statement(scaleDecoder: ScaleDecoder(data: existing.data))
            return existingStatement.getChannel() == channel && existingStatement.getSenderAccountId() == sender
        }

        guard let replaced else {
            return
        }

        let replacedExpiry = try Statement(scaleDecoder: ScaleDecoder(data: replaced.data)).getExpiry() ?? 0

        guard (decoded.getExpiry() ?? 0) > replacedExpiry else {
            throw StatementSubmitError.rejected(.channelPriorityTooLow)
        }

        statements.remove(replaced)
    }

    private func takeObservers() -> [Observer] {
        mutex.lock()
        defer { mutex.unlock() }

        let taken = observers
        observers = []
        return taken
    }
}

extension MockStatementStore: StatementStoreSubmitting {
    nonisolated func submitStatement(with builder: StatementSubmitParametersBuilding) async throws {
        try insertStatement(with: builder)
    }
}

extension MockStatementStore: StatementStoreFetching {
    nonisolated func fetchStatements(with filter: TopicFilter) async throws -> [Data] {
        try getStatements(with: filter)
    }

    nonisolated func subscribeStatements(with filter: TopicFilter) -> AnyAsyncSequence<StatementsPage> {
        AsyncThrowingStream { continuation in
            let observer = Observer(filter: filter, continuation: continuation)

            self.addObserver(observer)

            continuation.onTermination = { _ in
                self.removeObserver(observer)
            }
        }
        .map { StatementsPage(statements: $0, isComplete: true) }
        .eraseToAnyAsyncSequence()
    }
}
