import Foundation
import SubstrateSdk
import AsyncExtensions

final class CallMediaStateChannel {
    static let useCaseId = "webrtc_media_state_use_case"

    private let multiplexedChannel: MultiplexedDataChannel
    private let logger: LoggerProtocol

    private let subscribedStream: AnyAsyncSequence<Data>

    init(multiplexedChannel: MultiplexedDataChannel, logger: LoggerProtocol) {
        self.multiplexedChannel = multiplexedChannel
        self.logger = logger
        subscribedStream = multiplexedChannel.subscribe(useCaseId: Self.useCaseId)
    }

    var signals: AnyAsyncSequence<CallMediaStateSignal> {
        subscribedStream
            .compactMap { [logger] data in
                do {
                    let decoder = try ScaleDecoder(data: data)
                    return try CallMediaStateSignal(scaleDecoder: decoder)
                } catch {
                    logger.error("Media state decoding failed: \(error)")
                    return nil
                }
            }
            .eraseToAnyAsyncSequence()
    }

    func send(_ signal: CallMediaStateSignal) async throws {
        let data = try signal.scaleEncoded()
        try await multiplexedChannel.send(data: data, useCaseId: Self.useCaseId)
    }
}
