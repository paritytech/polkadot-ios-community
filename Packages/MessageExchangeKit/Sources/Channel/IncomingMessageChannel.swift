import Foundation
import CryptoKit
import Operation_iOS
import StatementStore
import SDKLogger

final class IncomingMessageChannel<M: MessageExchange.CodableMessage>: @unchecked Sendable {
    typealias Message = M

    weak var delegate: AnyIncomingMessageChannelDelegate<M>?

    private let workQueue: DispatchQueue
    private let sessionId: MessageExchange.SessionId
    private let channelId: StatementFixedFieldConvertible
    private let submitter: StatementStoreSubmitting
    private let signer: StatementStoreSigning
    private let priorityProvider: PeerSessionPriorityProviding
    private let statementDataCoder: StatementDataCoding
    private let operationQueue: OperationQueue
    private let logger: SDKLoggerProtocol?

    private var submissionTask: Task<Void, Never>?

    init(
        workQueue: DispatchQueue,
        sessionId: MessageExchange.SessionId,
        channelId: StatementFixedFieldConvertible,
        submitter: StatementStoreSubmitting,
        signer: StatementStoreSigning,
        priorityProvider: PeerSessionPriorityProviding,
        statementDataCoder: StatementDataCoding,
        operationQueue: OperationQueue,
        logger: SDKLoggerProtocol?
    ) {
        self.workQueue = workQueue
        self.sessionId = sessionId
        self.channelId = channelId
        self.submitter = submitter
        self.signer = signer
        self.priorityProvider = priorityProvider
        self.statementDataCoder = statementDataCoder
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension IncomingMessageChannel: IncomingMessageChanneling {
    func sendResponse(
        with responseCode: MessageExchange.ResponseCode,
        forRequestId requestId: String
    ) {
        assert(delegate != nil, "Delegate should not be nil")

        guard let scaleEncodedPayload = makeScaleEncodedPayload(response: .init(
            requestId: requestId,
            responseCode: responseCode
        )) else {
            return
        }

        let expiry = priorityProvider.incrementedExpiry()

        let builder = StatementSubmitParametersBuilder(
            signer: signer,
            logger: logger
        )
        .addTopic1(sessionId.own)
        .addChannel(channelId)
        .addExpiry(expiry)
        .addScaleEncodedPayload(scaleEncodedPayload)

        logger?.debug("Going to send \(responseCode) for request \(requestId) with priority \(expiry)")

        // it is ok to cancel submission task since we can have this case
        // only when a peer replaced the statement we were responding to
        submissionTask?.cancel()
        submissionTask = Task { [weak self] in
            do {
                try await self?.submitter.submitStatement(with: builder)
                self?.logger?.debug("\(responseCode) sent for request \(requestId)")
            } catch {
                guard !Task.isCancelled else { return }
                self?.logger?.error("Failed to send \(responseCode) for request \(requestId): \(error)")
                self?.workQueue.async {
                    self?.delegate?.statementSubmitFailed(with: error)
                }
            }
        }
    }
}

private extension IncomingMessageChannel {
    func makeScaleEncodedPayload(response: MessageExchange.Response) -> Data? {
        do {
            let statementData = StatementData<Message>.response(response)
            return try statementDataCoder.encodeToScaleEncodedPayload(statementData)
        } catch {
            logger?.error("Failed to encode response: \(error)")
            return nil
        }
    }
}
