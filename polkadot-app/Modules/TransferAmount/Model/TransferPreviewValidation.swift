import BigInt
import Coinage

enum TransferPreviewValidation {
    case coinage(TransferPreview)
    case externalPayment(ExternalPaymentPreview)

    var fullAmount: BigUInt {
        switch self {
        case let .coinage(preview): preview.fullAmount
        case let .externalPayment(preview): preview.fullAmount
        }
    }
}
