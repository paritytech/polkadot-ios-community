import BigInt
import Coinage

enum TransferPreviewValidation {
    case coinage(TransferPreview)
    /// External payments carry the strategy-driven consent flag: any preset but minPrivacy confirms.
    case externalPayment(ExternalPaymentPreview, requiresPrivacyConfirmation: Bool)

    var fullAmount: BigUInt {
        switch self {
        case let .coinage(preview): preview.fullAmount
        case let .externalPayment(preview, _): preview.fullAmount
        }
    }

    /// Whether the plan spends gaining-privacy funds, so the user must confirm before it is submitted.
    var requiresPrivacyConfirmation: Bool {
        switch self {
        case let .coinage(preview): preview.scope == .withConfirmation
        case let .externalPayment(_, requiresPrivacyConfirmation): requiresPrivacyConfirmation
        }
    }
}
