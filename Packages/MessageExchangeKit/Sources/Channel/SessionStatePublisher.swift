import Foundation
import StatementStore
import SDKLogger

protocol SessionStatePublisherDelegate: AnyObject {
    func publisher(didPostRequest requestId: String, route: PeerSessionRoute)
    func publisher(didFailRequest requestId: String, route: PeerSessionRoute, error: Error)
    func publisher(didFailSubmissionWith error: Error)
}

protocol SessionStatePublishing<Message>: AnyObject {
    associatedtype Message: MessageExchange.CodableMessage

    var delegate: SessionStatePublisherDelegate? { get set }

    /// Sets the pending request and publishes the state carrying it.
    func publishRequest(_ request: OutgoingRequest<Message>)

    /// Adopts our latest published states after a restart, without publishing; restored acks stay sticky.
    func restore(_ states: [PeerSessionRoute: MessageExchange.SessionState<Message>])

    /// Drops the pending request once it is acked; the next publish carries no request.
    func clearRequest(requestId: String, route: PeerSessionRoute)

    /// Replaces the owed ack and publishes; the ack stays in every later state until replaced.
    func publishResponse(_ response: MessageExchange.Response, route: PeerSessionRoute)

    func reset(route: PeerSessionRoute)
}

/// Builds and submits the single state statement per route: the pending request and the owed ack together.
final class SessionStatePublisher<M: MessageExchange.CodableMessage>: @unchecked Sendable {
    typealias Message = M

    weak var delegate: SessionStatePublisherDelegate?

    private struct RouteState {
        var request: OutgoingRequest<M>?
        var response: MessageExchange.Response?
        var lastPublishedPlaintext: Data?
        var postedRequestId: String?
        var submission: Task<Void, Never>?
    }

    private let workQueue: DispatchQueue
    private let routeContexts: PeerSessionRoute.Contexts
    private let submitter: PeerSessionStatementSubmitting
    private let priorityProvider: PeerSessionPriorityProviding
    private let statementDataCoder: StatementDataCoding
    private let logger: SDKLoggerProtocol?

    private var routeStates = [PeerSessionRoute: RouteState]()

    init(
        workQueue: DispatchQueue,
        routeContexts: PeerSessionRoute.Contexts,
        submitter: PeerSessionStatementSubmitting,
        priorityProvider: PeerSessionPriorityProviding,
        statementDataCoder: StatementDataCoding,
        logger: SDKLoggerProtocol?
    ) {
        self.workQueue = workQueue
        self.routeContexts = routeContexts
        self.submitter = submitter
        self.priorityProvider = priorityProvider
        self.statementDataCoder = statementDataCoder
        self.logger = logger
    }
}

extension SessionStatePublisher: SessionStatePublishing {
    func publishRequest(_ request: OutgoingRequest<M>) {
        routeStates[request.route, default: .init()].request = request
        publish(route: request.route)
    }

    func restore(_ states: [PeerSessionRoute: MessageExchange.SessionState<M>]) {
        for (route, state) in states {
            let request = state.request.map {
                OutgoingRequest(requestId: $0.requestId, messages: $0.messages, route: route)
            }

            routeStates[route] = RouteState(
                request: request,
                response: state.response,
                lastPublishedPlaintext: try? StatementData<M>.state(state).scaleEncoded(),
                postedRequestId: request?.requestId
            )
        }
    }

    func clearRequest(requestId: String, route: PeerSessionRoute) {
        guard routeStates[route]?.request?.requestId == requestId else {
            return
        }

        routeStates[route]?.request = nil
    }

    func publishResponse(_ response: MessageExchange.Response, route: PeerSessionRoute) {
        routeStates[route, default: .init()].response = response
        publish(route: route)
    }

    func reset(route: PeerSessionRoute) {
        routeStates[route]?.submission?.cancel()
        routeStates[route]?.submission = nil
        routeStates[route]?.request = nil
        routeStates[route]?.lastPublishedPlaintext = nil
    }
}

private extension SessionStatePublisher {
    func publish(route: PeerSessionRoute) {
        guard let routeState = routeStates[route] else {
            return
        }

        let requestId = routeState.request?.requestId
        let state = MessageExchange.SessionState(
            response: routeState.response,
            request: routeState.request.map { .init(requestId: $0.requestId, messages: $0.messages) }
        )

        do {
            let plaintext = try StatementData<M>.state(state).scaleEncoded()

            // Ciphertexts differ on every encryption, so unchanged states are detected on the plaintext.
            guard plaintext != routeState.lastPublishedPlaintext else {
                logger?.debug("State on route \(route) is unchanged, skipping publish")
                return
            }

            let statement = try makeStatement(for: state, route: route)
            routeStates[route]?.lastPublishedPlaintext = plaintext
            submit(statement, carryingRequestId: requestId, route: route)
        } catch {
            logger?.error("Failed to encode state on route \(route): \(error)")
            notifyFailure(error, requestId: requestId, route: route)
        }
    }

    func makeStatement(
        for state: MessageExchange.SessionState<M>,
        route: PeerSessionRoute
    ) throws -> UnsignedStatement {
        let payload = try statementDataCoder.encodeToScaleEncodedPayload(StatementData<M>.state(state), route: route)
        let routeContext = routeContexts.context(for: route)
        let expiry = try priorityProvider.incrementedExpiry()

        return UnsignedStatement()
            .addTopic1(routeContext.sessionId.own)
            .addChannel(routeContext.channelId)
            .addExpiry(expiry)
            .addScaleEncodedPayload(payload)
    }

    func submit(_ statement: UnsignedStatement, carryingRequestId requestId: String?, route: PeerSessionRoute) {
        routeStates[route]?.submission?.cancel()
        routeStates[route]?.submission = Task { [weak self] in
            do {
                try await self?.submitter.submit(statement)
                self?.workQueue.async {
                    self?.handleSubmitted(requestId: requestId, route: route)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.workQueue.async {
                    self?.routeStates[route]?.lastPublishedPlaintext = nil
                    self?.notifyFailure(error, requestId: requestId, route: route)
                }
            }
        }
    }

    func handleSubmitted(requestId: String?, route: PeerSessionRoute) {
        guard let requestId, routeStates[route]?.postedRequestId != requestId else {
            return
        }

        routeStates[route]?.postedRequestId = requestId
        delegate?.publisher(didPostRequest: requestId, route: route)
    }

    func notifyFailure(_ error: Error, requestId: String?, route: PeerSessionRoute) {
        if let requestId {
            delegate?.publisher(didFailRequest: requestId, route: route, error: error)
        }

        delegate?.publisher(didFailSubmissionWith: error)
    }
}
