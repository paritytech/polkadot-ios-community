import Foundation
import SubstrateSdk

public extension MessageExchange {
    /// The sender's whole outbound state toward a peer on one route, published as a single statement.
    struct SessionState<M: MessageExchange.CodableMessage> {
        public let response: Response?
        public let request: Request<M>?

        public init(response: Response?, request: Request<M>?) {
            self.response = response
            self.request = request
        }
    }
}

// The response is encoded first so it stays decodable when the request's messages are not.
extension MessageExchange.SessionState: ScaleCodable {
    public init(scaleDecoder: any ScaleDecoding) throws {
        response = try ScaleOption<MessageExchange.Response>(scaleDecoder: scaleDecoder).value
        request = try ScaleOption<MessageExchange.Request<M>>(scaleDecoder: scaleDecoder).value
    }

    public func encode(scaleEncoder: any ScaleEncoding) throws {
        try ScaleOption(value: response).encode(scaleEncoder: scaleEncoder)
        try ScaleOption(value: request).encode(scaleEncoder: scaleEncoder)
    }
}

/// What survives when a state's messages can't be decoded: the full response and the request id.
struct SessionStateFallbackData: ScaleDecodable {
    let response: MessageExchange.Response?
    let requestId: String?

    init(scaleDecoder: any ScaleDecoding) throws {
        response = try ScaleOption<MessageExchange.Response>(scaleDecoder: scaleDecoder).value
        requestId = try ScaleOption<RequestIdPrefix>(scaleDecoder: scaleDecoder).value?.requestId
    }
}

private struct RequestIdPrefix: ScaleCodable {
    let requestId: String

    init(scaleDecoder: any ScaleDecoding) throws {
        requestId = try String(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try requestId.encode(scaleEncoder: scaleEncoder)
    }
}

extension MessageExchange.SessionState: Equatable {}
