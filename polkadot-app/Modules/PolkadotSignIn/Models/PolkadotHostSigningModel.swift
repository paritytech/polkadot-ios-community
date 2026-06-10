import Foundation
import Products

enum PolkadotHostSigningModel {
    case signingRequest(PolkadotHostRemoteMessage.SigningRequest)
    case createTransaction(CreateTransactionPayload<ProductAccountId>)

    var account: ProductAccountId {
        switch self {
        case let .signingRequest(request):
            request.account
        case let .createTransaction(payload):
            payload.signer
        }
    }
}
