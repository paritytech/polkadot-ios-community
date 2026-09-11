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

    /// Whether the plan spends gaining-privacy funds, so the user must confirm before it is submitted.
    var requiresPrivacyConfirmation: Bool {
        switch self {
        case let .coinage(preview): preview.scope == .withConfirmation
        case let .externalPayment(preview): preview.scope == .withConfirmation
        }
    }
}
