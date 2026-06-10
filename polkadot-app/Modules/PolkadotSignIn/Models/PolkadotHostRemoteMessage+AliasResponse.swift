import Foundation
import MessageExchangeKit
import SubstrateSdk

extension PolkadotHostRemoteMessage {
    struct ContextualAlias {
        static let contextSize = 32

        let context: Data
        let alias: Data
    }
}

extension PolkadotHostRemoteMessage.ContextualAlias: MessageExchange.CodableMessage {
    init(scaleDecoder: any ScaleDecoding) throws {
        context = try scaleDecoder.readAndConfirm(count: Self.contextSize)
        alias = try Data(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: context)
        try alias.encode(scaleEncoder: scaleEncoder)
    }
}
