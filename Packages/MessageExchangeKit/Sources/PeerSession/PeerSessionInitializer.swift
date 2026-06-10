import Foundation
import SubstrateSdk
import StatementStore
import SDKLogger

protocol PeerSessionInitializing {
    func initializeSession()
    func setLastHandledResponseId(_ responseId: String?)
}

struct SessionInitializationSuccess<Message: MessageExchange.CodableMessage> {
    let outgoingState: OutgoingInitializationState<Message>
    let incomingState: IncomingInitializationState<Message>
    let priority: UInt64

    init(
        outgoingState: OutgoingInitializationState<Message>,
        incomingState: IncomingInitializationState<Message>,
        priority: UInt64
    ) {
        self.outgoingState = outgoingState
        self.incomingState = incomingState
        self.priority = priority
    }

    init(priority: UInt64) {
        outgoingState = .empty
        incomingState = .empty

        self.priority = priority
    }
}

struct OutgoingInitializationState<Message: MessageExchange.CodableMessage> {
    let outgoingRequest: OutgoingRequest<Message>?
    let peerResponse: MessageExchange.Response?
    let initializedMessages: [Message]

    static var empty: Self {
        .init(
            outgoingRequest: nil,
            peerResponse: nil,
            initializedMessages: []
        )
    }
}

struct IncomingInitializationState<Message: MessageExchange.CodableMessage> {
    let peerRequests: [MessageExchange.Request<Message>]

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
    private let ownPoller: StatementSubscribing
    private let peerSubscription: StatementSubscribing
    private let workQueue: DispatchQueue
    private let statementDataCoder: StatementDataCoding
    private let logger: SDKLoggerProtocol?

    private var isInitializing = false
    private var lastHandledResponseId: String?

    init(
        priorityProvider: PeerSessionPriorityProviding,
        ownPoller: StatementSubscribing,
        peerSubscription: StatementSubscribing,
        workQueue: DispatchQueue,
        statementDataCoder: StatementDataCoding,
        logger: SDKLoggerProtocol?
    ) {
        self.priorityProvider = priorityProvider
        self.ownPoller = ownPoller
        self.peerSubscription = peerSubscription
        self.workQueue = workQueue
        self.statementDataCoder = statementDataCoder
        self.logger = logger
    }
}

extension PeerSessionInitializer: PeerSessionInitializing {
    func initializeSession() {
        workQueue.async { [weak self] in
            self?.performSessionInitialization()
        }
    }

    func setLastHandledResponseId(_ responseId: String?) {
        lastHandledResponseId = responseId
    }
}

private extension PeerSessionInitializer {
    func performSessionInitialization() {
        guard !isInitializing else {
            logger?.debug("Already initializing")
            return
        }

        isInitializing = true

        ownPoller.resetSeenHashes()
        peerSubscription.resetSeenHashes()

        let group = DispatchGroup()

        var ownStatements = [Statement]()
        var ownError: StatementSubscriptionError?

        var peerStatements = [Statement]()
        var peerError: StatementSubscriptionError?

        group.enter()
        ownPoller.fetchOnce(handler: {
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
                ownError: ownError,
                peerError: peerError
            )
        }
    }

    func continueAfterFetch(
        ownStatements: [Statement],
        peerStatements: [Statement],
        ownError: StatementSubscriptionError?,
        peerError: StatementSubscriptionError?
    ) {
        logger?.debug("Own statements count \(ownStatements.count)")
        logger?.debug("Peer statements count \(peerStatements.count)")
        if let ownError { logger?.error("Own error: \(ownError)") }
        if let peerError { logger?.error("Peer error: \(peerError)") }

        let expiry = priorityProvider.initialExpiry(from: ownStatements)

        logger?.debug("Resolved priority: \(expiry)")

        do {
            if let pollingError = ownError ?? peerError {
                throw pollingError
            }

            let sortedOwnStatements = ownStatements
                .sorted { ($0.getExpiry() ?? 0) > ($1.getExpiry() ?? 0) }
            let sortedPeerStatements = peerStatements
                .sorted { ($0.getExpiry() ?? 0) > ($1.getExpiry() ?? 0) }

            let ownStatementDataList = try makeStatementDataList(from: sortedOwnStatements)
            let peerStatementDataList = try makeStatementDataList(from: sortedPeerStatements)

            let incomingState = try makeIncomingState(
                ownStatementDataList: ownStatementDataList,
                peerStatementDataList: peerStatementDataList
            )

            let outgoingState = try makeOutgoingState(
                ownStatementDataList: ownStatementDataList,
                peerStatementDataList: peerStatementDataList,
                ownStatements: sortedOwnStatements
            )

            isInitializing = false

            delegate?.sessionInitializer(
                self,
                didInitializeWith: .init(
                    outgoingState: outgoingState,
                    incomingState: incomingState,
                    priority: expiry
                )
            )
        } catch {
            isInitializing = false

            let initError = makeInitializationError(error: error)
            logger?.error("Session initialization failed: \(initError) (underlying: \(error))")

            delegate?.sessionInitializer(
                self,
                didFailToInitializeWith: .init(
                    error: initError,
                    expiry: expiry
                )
            )
        }
    }

    func makeStatementDataList(from statements: [Statement]) throws -> [StatementData<Message>] {
        try statements.compactMap { statement -> StatementData<Message>? in
            try statement.getScaleEncodedPayload().map {
                let senderAccountId = statement.getSenderAccountId()
                let result: StatementDataDecodingResult<Message> = try statementDataCoder
                    .decodeFromScaleEncodedPayload($0, senderAccountId: senderAccountId)

                switch result {
                case let .statementData(statementData):
                    return statementData
                case let .requestId(requestId, _):
                    // it is ok to return statement data for compatibility reason here
                    // since we don't respond to requests in the initializer
                    return StatementData.request(
                        .init(requestId: requestId, messages: [])
                    )
                }
            }
        }
    }

    func makeIncomingState(
        ownStatementDataList: [StatementData<Message>],
        peerStatementDataList: [StatementData<Message>]
    ) throws -> IncomingInitializationState<Message> {
        let pendingPeerRequests = peerStatementDataList.compactMap { statementData
            -> MessageExchange.Request<Message>? in
            guard case let .request(peerRequest) = statementData else {
                return nil
            }

            let responseStatementData = matchingResponseStatementData(
                forRequestStatementData: statementData,
                in: ownStatementDataList
            )

            if responseStatementData == nil {
                return peerRequest
            } else {
                return nil
            }
        }

        guard !pendingPeerRequests.isEmpty else {
            return .empty
        }

        return .init(peerRequests: pendingPeerRequests)
    }

    func makeOutgoingState(
        ownStatementDataList: [StatementData<Message>],
        peerStatementDataList: [StatementData<Message>],
        ownStatements: [Statement]
    ) throws -> OutgoingInitializationState<Message> {
        guard let index = ownStatementDataList.firstIndex(where: { statementData in
            if case .request = statementData {
                true
            } else {
                false
            }
        }) else {
            return .empty
        }

        let outgoingRequestStatementData = ownStatementDataList[index]
        let outgoingRequestStatement = ownStatements[index]

        guard
            case let .request(request) = outgoingRequestStatementData,
            let scaleEncodedPayload = outgoingRequestStatement.getScaleEncodedPayload()
        else {
            return .empty
        }

        // TODO: Response statements share the same response channel, so init
        // can only match request ids whose ACK is still visible in fetched peer
        // statements. Revisit this if sender-side ACK recovery must cover every
        // outstanding request id.
        let responseStatementData = matchingResponseStatementData(
            forRequestStatementData: outgoingRequestStatementData,
            in: peerStatementDataList
        )

        let outgoingRequest: OutgoingRequest<Message>?
        let peerResponse: MessageExchange.Response?
        let initializedMessages: [Message]

        if case let .response(response) = responseStatementData {
            if response.requestId == lastHandledResponseId {
                // request/response pair already handled
                outgoingRequest = nil
                peerResponse = nil
            } else {
                outgoingRequest = .init(
                    requestId: request.requestId,
                    messages: request.messages,
                    scaleEncodedPayload: scaleEncodedPayload
                )
                peerResponse = response
            }
            initializedMessages = []
        } else {
            outgoingRequest = .init(
                requestId: request.requestId,
                messages: request.messages,
                scaleEncodedPayload: scaleEncodedPayload
            )
            peerResponse = nil
            initializedMessages = request.messages
        }

        return .init(
            outgoingRequest: outgoingRequest,
            peerResponse: peerResponse,
            initializedMessages: initializedMessages
        )
    }

    func matchingResponseStatementData(
        forRequestStatementData requestStatementData: StatementData<Message>,
        in statementDataList: [StatementData<Message>]
    ) -> StatementData<Message>? {
        statementDataList.first(where: { statementData in
            if case let .response(response) = statementData,
               case let .request(request) = requestStatementData,
               response.requestId == request.requestId {
                true
            } else {
                false
            }
        })
    }

    func makeInitializationError(error: Error) -> MessageExchange.InitializationError {
        switch error {
        case let initializationError as MessageExchange.InitializationError:
            initializationError
        case let pollingError as StatementSubscriptionError:
            makeInitializationError(pollingError: pollingError)
        case let incomingMessageError as MessageExchange.IncomingMessageError:
            makeInitializationError(incomingMessageError: incomingMessageError)
        case let decodingError as StatementDataDecodingError:
            makeInitializationError(decodingError: decodingError)
        default:
            .other(error)
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

    func makeInitializationError(incomingMessageError: MessageExchange.IncomingMessageError) -> MessageExchange
        .InitializationError {
        switch incomingMessageError {
        case .decryptionFailed:
            .statementPayloadDecryptionFailed
        case .decodingFailed:
            .statementPayloadDecodingFailed
        }
    }

    func makeInitializationError(decodingError: StatementDataDecodingError) -> MessageExchange.InitializationError {
        switch decodingError {
        case .decodingFailed:
            .statementPayloadDecodingFailed
        case .decryptionFailed:
            .statementPayloadDecryptionFailed
        }
    }
}
