import Foundation
import MessageExchangeKit
import Products
import SubstrateSdk

extension PolkadotHostRemoteMessage {
    struct AliasRequest {
        let accountId: ProductAccountId
        let callingProductId: ProductId
    }
}

extension PolkadotHostRemoteMessage.AliasRequest: MessageExchange.CodableMessage {
    init(scaleDecoder: any ScaleDecoding) throws {
        let productId = try String(scaleDecoder: scaleDecoder)
        let derivationIndex = try UInt32(scaleDecoder: scaleDecoder)
        accountId = ProductAccountId(productId: productId, derivationIndex: derivationIndex)
        callingProductId = try String(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try accountId.productId.encode(scaleEncoder: scaleEncoder)
        try accountId.derivationIndex.encode(scaleEncoder: scaleEncoder)
        try callingProductId.encode(scaleEncoder: scaleEncoder)
    }
}
