import Foundation
import SubstrateSdk
import StatementStore
import SDKLogger

protocol PeerSessionInitializing {
    func initializeSession()
    func setLastHandledResponseId(_ responseId: String?, route: PeerSessionRoute)
}

struct SessionInitializationSuccess<Message: MessageExchange.CodableMessage> {
    let outgoingState: OutgoingInitializationState<Message>
    let incomingState: IncomingInitializationState<Message>
    /// Our latest published state per route, for the publisher to continue from.
    let ownStates: [PeerSessionRoute: MessageExchange.SessionState<Message>]
    let priority: UInt64

    init(
        outgoingState: OutgoingInitializationState<Message>,
        incomingState: IncomingInitializationState<Message>,
        ownStates: [PeerSessionRoute: MessageExchange.SessionState<Message>],
        priority: UInt64
    ) {
        self.outgoingState = outgoingState
        self.incomingState = incomingState
        self.ownStates = ownStates
        self.priority = priority
    }

    init(priority: UInt64) {
        outgoingState = .empty
        incomingState = .empty
        ownStates = [:]

        self.priority = priority
    }
}

struct OutgoingInitializationState<Message: MessageExchange.CodableMessage> {
    let outgoingRequests: [PeerSessionRoute: OutgoingRequest<Message>]
    let peerResponses: [PeerSessionRoute: MessageExchange.Response]
    let initializedMessages: [Message]

    static var empty: Self {
        .init(
            outgoingRequests: [:],
            peerResponses: [:],
            initializedMessages: []
        )
    }
}

struct IncomingInitializationState<Message: MessageExchange.CodableMessage> {
    let peerRequests: [PeerSessionRequest<Message>]

    static var empty: Self {
        .init(
            peerRequests: []
        )
    }
}

struct SessionInitializationFailure {
    let error: MessageExchange.InitializationError
    let expiry: UInt64
}

final class PeerSessionInitializer<M: MessageExchange.CodableMessage> {
    typealias Message = M

    weak var delegate: AnyPeerSessionInitializerDelegate<M>?

    private let priorityProvider: PeerSessionPriorityProviding
    private let ownSubscription: any PeerSessionStatementSubscribing
    private let peerSubscription: any PeerSessionStatementSubscribing
    private let workQueue: DispatchQueue
    private let statementDataCoder: StatementDataCoding
    private let supportedRoutes: [PeerSessionRoute]
    private let logger: SDKLoggerProtocol?

    private var isInitializing = false
    private var lastHandledResponseIds = [PeerSessionRoute: String]()

    init(
        priorityProvider: PeerSessionPriorityProviding,
        ownSubscription: any PeerSessionStatementSubscribing,
        peerSubscription: any PeerSessionStatementSubscribing,
        workQueue: DispatchQueue,
        statementDataCoder: StatementDataCoding,
        supportedRoutes: [PeerSessionRoute],
        logger: SDKLoggerProtocol?
    ) {
        self.priorityProvider = priorityProvider
        self.ownSubscription = ownSubscription
        self.peerSubscription = peerSubscription
        self.workQueue = workQueue
        self.statementDataCoder = statementDataCoder
        self.supportedRoutes = supportedRoutes
        self.logger = logger
    }
}

extension PeerSessionInitializer: PeerSessionInitializing {
    func initializeSession() {
        workQueue.async { [weak self] in
            self?.performSessionInitialization()
        }
    }

    func setLastHandledResponseId(
        _ responseId: String?,
        route: PeerSessionRoute
    ) {
        lastHandledResponseIds[route] = responseId
    }
}

private extension PeerSessionInitializer {
    /// A statement that decrypted under the session key: decryption is the only proof it came from us or the peer.
    struct AuthenticState {
        let state: MessageExchange.SessionState<Message>
        let statement: Statement
        let route: PeerSessionRoute
        let topicAccountId: AccountId
    }

    struct TopicKey: Hashable {
        let route: PeerSessionRoute
        let topicAccountId: AccountId
    }

    func performSessionInitialization() {
        guard !isInitializing else {
            logger?.debug("Already initializing")
            return
        }

        isInitializing = true

        ownSubscription.resetSeenHashes()
        peerSubscription.resetSeenHashes()

        let group = DispatchGroup()

        var ownStatements = [PeerSessionStatement]()
        var ownError: StatementSubscriptionError?

        var peerStatements = [PeerSessionStatement]()
        var peerError: StatementSubscriptionError?

        group.enter()
        ownSubscription.fetchOnce(handler: {
            ownStatements.append($0)
            return true
        }, completion: { error in
            ownError = error
            group.leave()
        })

        group.enter()
        peerSubscription.fetchOnce(handler: {
            peerStatements.append($0)
            return true
        }, completion: { error in
            peerError = error
            group.leave()
        })

        group.notify(queue: workQueue) { [weak self] in
            self?.continueAfterFetch(
                ownStatements: ownStatements,
                peerStatements: peerStatements,
                pollingError: [ownError, peerError].compactMap { $0 }.first(where: Self.isFatal)
            )
        }
    }

    func continueAfterFetch(
        ownStatements: [PeerSessionStatement],
        peerStatements: [PeerSessionStatement],
        pollingError: StatementSubscriptionError?
    ) {
        logger?.debug("Own statements count \(ownStatements.count)")
        logger?.debug("Peer statements count \(peerStatements.count)")

        let ownStates = authenticStates(from: ownStatements)
        let expiry = priorityProvider.initialExpiry(from: ownStates.map(\.statement))

        logger?.debug("Resolved priority: \(expiry)")

        isInitializing = false

        if let pollingError {
            logger?.error("Session initialization failed: \(pollingError)")
            delegate?.sessionInitializer(
                self,
                didFailToInitializeWith: .init(
                    error: makeInitializationError(pollingError: pollingError),
                    expiry: expiry
                )
            )
            return
        }

        let latestOwnStates = latestStatePerRoute(in: ownStates)
        let latestPeerStates = latestStatePerTopic(in: authenticStates(from: peerStatements))
        let outgoingState = makeOutgoingState(ownStates: latestOwnStates, peerStates: latestPeerStates)

        delegate?.sessionInitializer(
            self,
            didInitializeWith: .init(
                outgoingState: outgoingState,
                incomingState: makeIncomingState(ownStates: latestOwnStates, peerStates: latestPeerStates),
                ownStates: restorableStates(latestOwnStates, pendingRequests: outgoingState.outgoingRequests),
                priority: expiry
            )
        )
    }

    /// Newest first; anything that fails to decrypt or decode is skipped, since anyone can publish under a topic.
    func authenticStates(from statements: [PeerSessionStatement]) -> [AuthenticState] {
        statements
            .compactMap { sessionStatement -> AuthenticState? in
                guard let state = decodeState(from: sessionStatement) else {
                    return nil
                }

                return AuthenticState(
                    state: state,
                    statement: sessionStatement.statement,
                    route: sessionStatement.route,
                    topicAccountId: sessionStatement.topicAccountId
                )
            }
            .sorted { ($0.statement.getExpiry() ?? 0) > ($1.statement.getExpiry() ?? 0) }
    }

    func decodeState(from sessionStatement: PeerSessionStatement) -> MessageExchange.SessionState<Message>? {
        guard let payload = sessionStatement.statement.getScaleEncodedPayload() else {
            return nil
        }

        do {
            let result: StatementDataDecodingResult<Message> = try statementDataCoder.decodeFromScaleEncodedPayload(
                payload,
                senderAccountId: sessionStatement.topicAccountId,
                route: sessionStatement.route
            )

            switch result {
            case let .statementData(.state(state)):
                return state
            case .statementData(.multistate):
                return nil
            case let .partial(response, requestId, _):
                // Messages are not needed here: restore only matches request ids against acks.
                return .init(response: response, request: .init(requestId: requestId, messages: []))
            }
        } catch {
            logger?.debug("Skipping undecodable statement on route \(sessionStatement.route): \(error)")
            return nil
        }
    }

    func latestStatePerRoute(in states: [AuthenticState]) -> [PeerSessionRoute: AuthenticState] {
        states.reduce(into: [:]) { result, state in
            if result[state.route] == nil {
                result[state.route] = state
            }
        }
    }

    // Every peer device publishes its own state on its own topic.
    func latestStatePerTopic(in states: [AuthenticState]) -> [AuthenticState] {
        var seen = Set<TopicKey>()

        return states.filter { seen.insert(TopicKey(route: $0.route, topicAccountId: $0.topicAccountId)).inserted }
    }

    func makeOutgoingState(
        ownStates: [PeerSessionRoute: AuthenticState],
        peerStates: [AuthenticState]
    ) -> OutgoingInitializationState<Message> {
        var outgoingRequests = [PeerSessionRoute: OutgoingRequest<Message>]()
        var peerResponses = [PeerSessionRoute: MessageExchange.Response]()
        var initializedMessages = [Message]()

        for route in supportedRoutes {
            guard let request = ownStates[route]?.state.request else {
                continue
            }

            let pendingRequest = OutgoingRequest(requestId: request.requestId, messages: request.messages, route: route)
            let peerResponse = peerStates
                .first { $0.route == route && $0.state.response?.requestId == request.requestId }?
                .state.response

            if let peerResponse {
                guard peerResponse.requestId != lastHandledResponseIds[route] else {
                    continue
                }

                outgoingRequests[route] = pendingRequest
                peerResponses[route] = peerResponse
            } else {
                outgoingRequests[route] = pendingRequest
                initializedMessages += request.messages
            }
        }

        return .init(
            outgoingRequests: outgoingRequests,
            peerResponses: peerResponses,
            initializedMessages: initializedMessages
        )
    }

    func makeIncomingState(
        ownStates: [PeerSessionRoute: AuthenticState],
        peerStates: [AuthenticState]
    ) -> IncomingInitializationState<Message> {
        let pendingPeerRequests = peerStates.compactMap { peerState -> PeerSessionRequest<Message>? in
            guard
                let request = peerState.state.request,
                ownStates[peerState.route]?.state.response?.requestId != request.requestId
            else {
                return nil
            }

            return .init(request: request, route: peerState.route)
        }

        return .init(peerRequests: pendingPeerRequests)
    }

    /// Our states without requests the restore already treats as finished, so they are not republished.
    func restorableStates(
        _ ownStates: [PeerSessionRoute: AuthenticState],
        pendingRequests: [PeerSessionRoute: OutgoingRequest<Message>]
    ) -> [PeerSessionRoute: MessageExchange.SessionState<Message>] {
        ownStates.mapValues { ownState in
            let isPending = pendingRequests[ownState.route]?.requestId == ownState.state.request?.requestId
            return .init(response: ownState.state.response, request: isPending ? ownState.state.request : nil)
        }
    }

    // A statement the store accepted but we can't parse is junk anyone could post; the rest was still delivered.
    static func isFatal(_ pollingError: StatementSubscriptionError) -> Bool {
        switch pollingError {
        case .statementDecodingFailed:
            false
        case .other:
            true
        }
    }

    func makeInitializationError(pollingError: StatementSubscriptionError) -> MessageExchange.InitializationError {
        switch pollingError {
        case .statementDecodingFailed:
            .statementDecodingFailed
        case let .other(error):
            .other(error)
        }
    }
}
