import Foundation
import SubstrateSdkExt

struct DeviceTransferSessionMessageDecoder: DeviceSyncEnvelopeDecoding {
    let rejections: AsyncStream<Void>.Continuation

    func decodeEnvelope(from data: Data) throws -> Chat.DeviceSyncSignalingEnvelope? {
        switch try DeviceTransferSessionMessage.fromScaleEncoded(data) {
        case .rejected:
            rejections.yield()
            return nil
        case let .signaling(envelope):
            return envelope
        }
    }
}
