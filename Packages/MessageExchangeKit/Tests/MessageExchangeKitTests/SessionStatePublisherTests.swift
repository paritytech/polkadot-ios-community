import Foundation
import os
import StatementStore
import Testing
@testable import MessageExchangeKit

struct SessionStatePublisherTests {
    let workQueue = DispatchQueue(label: "test.session-state-publisher")
    let coder = RecordingStateCoder()
    let submitter = ScriptedSubmitter()
    let expiry = CountingExpiryProvider()
    let events = PublisherEventRecorder()

    @Test func requestIsPublishedAlone() async throws {
        let publisher = makePublisher()

        await run { publisher.publishRequest(request("r1")) }
        try await submitter.waitForSubmissions(1)

        #expect(coder.states == [state(response: nil, request: "r1")])
    }

    @Test func ackIsPublishedTogetherWithThePendingRequest() async throws {
        let publisher = makePublisher()

        await run {
            publisher.publishRequest(request("r1"))
            publisher.publishResponse(ack("q1"), route: .device)
        }
        try await submitter.waitForSubmissions(2)

        #expect(coder.states.last == state(response: "q1", request: "r1"))
    }

    @Test func clearingTheRequestDoesNotPublish() async throws {
        let publisher = makePublisher()

        await run {
            publisher.publishRequest(request("r1"))
            publisher.clearRequest(requestId: "r1", route: .device)
            publisher.publishResponse(ack("q1"), route: .device)
        }
        try await submitter.waitForSubmissions(2)

        #expect(coder.states == [state(response: nil, request: "r1"), state(response: "q1", request: nil)])
    }

    @Test func unchangedStateIsNotRepublished() async throws {
        let publisher = makePublisher()

        await run {
            publisher.publishResponse(ack("q1"), route: .device)
            publisher.publishResponse(ack("q1"), route: .device)
            publisher.publishRequest(request("r1"))
        }
        try await submitter.waitForSubmissions(2)

        #expect(coder.states == [state(response: "q1", request: nil), state(response: "q1", request: "r1")])
    }

    @Test func restoredRequestIsCarriedByTheNextPublishWithoutPublishingItself() async throws {
        let publisher = makePublisher()

        await run {
            publisher.restoreRequest(request("r1"))
            publisher.publishResponse(ack("q1"), route: .device)
        }
        try await submitter.waitForSubmissions(1)

        #expect(coder.states == [state(response: "q1", request: "r1")])
    }

    @Test func everyPublishTakesAHigherExpiry() async throws {
        let publisher = makePublisher()

        await run {
            publisher.publishRequest(request("r1"))
            publisher.publishResponse(ack("q1"), route: .device)
            publisher.publishResponse(ack("q2"), route: .device)
        }
        try await submitter.waitForSubmissions(3)

        #expect(expiry.issued == [1, 2, 3])
    }

    @Test func postedIsReportedOncePerRequest() async throws {
        let publisher = makePublisher()

        await run { publisher.publishRequest(request("r1")) }
        try await events.waitFor(.posted("r1"))
        await run { publisher.publishResponse(ack("q1"), route: .device) }
        try await submitter.waitForSubmissions(2)
        await run {}

        #expect(events.recorded == [.posted("r1")])
    }

    @Test func failureReportsTheCarriedRequestAndAllowsRetry() async throws {
        let publisher = makePublisher()
        submitter.failNext()

        await run { publisher.publishRequest(request("r1")) }
        try await events.waitFor(.submissionFailed)
        await run { publisher.publishRequest(request("r1")) }
        try await submitter.waitForSubmissions(2)

        #expect(events.recorded.prefix(2) == [.requestFailed("r1"), .submissionFailed])
        #expect(coder.states.count == 2)
    }
}

private extension SessionStatePublisherTests {
    func makePublisher() -> SessionStatePublisher<TestMessage> {
        let context = PeerSessionRoute.Context(
            sessionId: MessageExchange.SessionId(
                own: Data(repeating: 1, count: 32),
                peer: Data(repeating: 2, count: 32),
                ownParameter: Data(),
                peerParameter: Data(),
                channelKey: Data(repeating: 3, count: 32)
            ),
            channelId: Data(repeating: 4, count: 32)
        )
        let publisher = SessionStatePublisher<TestMessage>(
            workQueue: workQueue,
            routeContexts: .init(device: context, identity: context),
            submitter: submitter,
            priorityProvider: expiry,
            statementDataCoder: coder,
            logger: nil
        )
        publisher.delegate = events
        return publisher
    }

    /// Runs on the publisher's queue, as the session does, and returns once the block has finished.
    func run(_ block: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            workQueue.async {
                block()
                continuation.resume()
            }
        }
    }

    func request(_ requestId: String) -> OutgoingRequest<TestMessage> {
        OutgoingRequest(requestId: requestId, messages: [TestMessage(id: 1)], route: .device)
    }

    func ack(_ requestId: String) -> MessageExchange.Response {
        MessageExchange.Response(requestId: requestId, responseCode: .success)
    }

    func state(response: String?, request: String?) -> MessageExchange.SessionState<TestMessage> {
        MessageExchange.SessionState(
            response: response.map(ack),
            request: request.map { .init(requestId: $0, messages: [TestMessage(id: 1)]) }
        )
    }
}

// MARK: - Test doubles

final class RecordingStateCoder: StatementDataCoding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [MessageExchange.SessionState<TestMessage>]())

    var states: [MessageExchange.SessionState<TestMessage>] { lock.withLock { $0 } }

    func decodeFromScaleEncodedPayload<M>(
        _: Data,
        senderAccountId _: Data?,
        route _: PeerSessionRoute
    ) throws -> StatementDataDecodingResult<M> where M: MessageExchange.CodableMessage {
        throw StatementDataDecodingError.decodingFailed
    }

    func encodeToScaleEncodedPayload(
        _ statementData: StatementData<some MessageExchange.CodableMessage>,
        route _: PeerSessionRoute
    ) throws -> Data {
        if case let .state(state) = statementData, let state = state as? MessageExchange.SessionState<TestMessage> {
            lock.withLock { $0.append(state) }
        }

        return Data([0])
    }
}

struct ScriptedFailure: Error {}

final class ScriptedSubmitter: PeerSessionStatementSubmitting, @unchecked Sendable {
    private struct State {
        var count = 0
        var failuresLeft = 0
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func failNext() {
        state.withLock { $0.failuresLeft += 1 }
    }

    func submit(_: UnsignedStatement) async throws {
        let (shouldFail, ready) = state.withLock { state -> (Bool, [CheckedContinuation<Void, Never>]) in
            state.count += 1
            let shouldFail = state.failuresLeft > 0
            state.failuresLeft = max(0, state.failuresLeft - 1)
            let count = state.count
            let ready = state.waiters.filter { $0.0 <= count }.map(\.1)
            state.waiters.removeAll { $0.0 <= count }
            return (shouldFail, ready)
        }

        ready.forEach { $0.resume() }

        if shouldFail {
            throw ScriptedFailure()
        }
    }

    func waitForSubmissions(_ count: Int) async throws {
        await withCheckedContinuation { continuation in
            let isReady = state.withLock { state -> Bool in
                guard state.count < count else { return true }
                state.waiters.append((count, continuation))
                return false
            }

            if isReady {
                continuation.resume()
            }
        }
    }
}

final class CountingExpiryProvider: PeerSessionPriorityProviding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [UInt64]())

    var expiry: UInt64 = 0
    var issued: [UInt64] { lock.withLock { $0 } }

    func initialExpiry(from _: [Statement]) -> UInt64 { 0 }

    func incrementedExpiry() -> UInt64 {
        lock.withLock { issued in
            let next = (issued.last ?? 0) + 1
            issued.append(next)
            return next
        }
    }
}

final class PublisherEventRecorder: SessionStatePublisherDelegate, @unchecked Sendable {
    enum Event: Equatable {
        case posted(String)
        case requestFailed(String)
        case submissionFailed
    }

    private struct State {
        var events: [Event] = []
        var waiters: [(Event, CheckedContinuation<Void, Never>)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var recorded: [Event] { state.withLock { $0.events } }

    func publisher(didPostRequest requestId: String, route _: PeerSessionRoute) {
        record(.posted(requestId))
    }

    func publisher(didFailRequest requestId: String, route _: PeerSessionRoute, error _: Error) {
        record(.requestFailed(requestId))
    }

    func publisher(didFailSubmissionWith _: Error) {
        record(.submissionFailed)
    }

    func waitFor(_ event: Event) async throws {
        await withCheckedContinuation { continuation in
            let isRecorded = state.withLock { state -> Bool in
                guard !state.events.contains(event) else { return true }
                state.waiters.append((event, continuation))
                return false
            }

            if isRecorded {
                continuation.resume()
            }
        }
    }

    private func record(_ event: Event) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.events.append(event)
            let ready = state.waiters.filter { $0.0 == event }.map(\.1)
            state.waiters.removeAll { $0.0 == event }
            return ready
        }

        ready.forEach { $0.resume() }
    }
}
