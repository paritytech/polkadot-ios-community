import BigInt
import Coinage

enum TransferPreviewValidation {
    case coinage(TransferPreview)
    case externalPayment(ExternalPaymentPreview)

    var isDegraded: Bool {
        switch self {
        case let .coinage(preview): preview.isDegraded
        case let .externalPayment(preview): preview.isDegraded
        }
    }

    var fullAmount: BigUInt {
        switch self {
        case let .coinage(preview): preview.fullAmount
        case let .externalPayment(preview): preview.fullAmount
        }
    }

    var nonDegradedAmount: BigUInt {
        switch self {
        case let .coinage(preview): preview.nonDegradedAmount
        case let .externalPayment(preview):
            // External payments require the exact requested amount.
            // Pass full amount as non-degraded to ensure the degraded
            // warning shows only the "Send with degraded" option.
            preview.nonDegradedAmount > .zero ? preview.fullAmount : .zero
        }
    }

    /// External payments require the exact requested amount — no partial send.
    var canSendNonDegraded: Bool {
        switch self {
        case .coinage: nonDegradedAmount > .zero
        case .externalPayment: false
        }
    }
}
