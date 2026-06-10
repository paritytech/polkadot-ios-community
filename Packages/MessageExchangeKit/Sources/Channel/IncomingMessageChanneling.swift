import Foundation

protocol IncomingMessageChanneling {
    associatedtype Message: MessageExchange.CodableMessage

    func sendResponse(
        with responseCode: MessageExchange.ResponseCode,
        forRequestId requestId: String
    )
}

// MARK: - Type Erasure Implementation

final class AnyIncomingMessageChannel<M: MessageExchange.CodableMessage>: IncomingMessageChanneling {
    typealias Message = M

    private let sendResponseClosure: (MessageExchange.ResponseCode, String) -> Void

    init<Channel: IncomingMessageChanneling>(_ targetChannel: Channel) where Channel.Message == M {
        sendResponseClosure = { code, requestId in
            targetChannel.sendResponse(with: code, forRequestId: requestId)
        }
    }

    func sendResponse(
        with responseCode: MessageExchange.ResponseCode,
        forRequestId requestId: String
    ) {
        sendResponseClosure(responseCode, requestId)
    }
}
