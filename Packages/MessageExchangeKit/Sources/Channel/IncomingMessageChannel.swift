import Foundation
import SDKLogger

/// Acks peer requests by putting the ack into the session state the publisher submits.
final class IncomingMessageChannel<M: MessageExchange.CodableMessage>: @unchecked Sendable {
    typealias Message = M

    private let publisher: any SessionStatePublishing<M>
    private let logger: SDKLoggerProtocol?

    init(
        publisher: any SessionStatePublishing<M>,
        logger: SDKLoggerProtocol?
    ) {
        self.publisher = publisher
        self.logger = logger
    }
}

extension IncomingMessageChannel: IncomingMessageChanneling {
    func sendResponse(
        with responseCode: MessageExchange.ResponseCode,
        forRequestId requestId: String,
        route: PeerSessionRoute
    ) {
        logger?.debug("Going to send \(responseCode) for request \(requestId)")

        publisher.publishResponse(
            MessageExchange.Response(requestId: requestId, responseCode: responseCode),
            route: route
        )
    }
}
