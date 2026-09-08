import Foundation

/// Product-supplied, opaque idempotency key for a top-up. Mirrors the host API `PaymentTopUpId`.
public typealias IncomingPaymentId = String

/// Material an incoming payment claims from. Both cases carry secret keys — the wallet case
/// resolves the external-asset holder from a single secret key (the app derives it from the
/// product derivation path), never from entropy.
public enum IncomingPaymentSource: Equatable, Sendable {
    case externalAssetFromWallet(secretKey: Data)
    case coinsFromPrivateKeys(secretKeys: [Data])
}

/// Durable discriminator persisted alongside a payment — lets the CoreData mapper name which shape
/// the stored secret blob has, and telemetry tell the two flows apart.
public enum IncomingPaymentSourceType: String, Sendable, Equatable {
    case externalAsset
    case coins
}

public extension IncomingPaymentSource {
    var sourceType: IncomingPaymentSourceType {
        switch self {
        case .externalAssetFromWallet: .externalAsset
        case .coinsFromPrivateKeys: .coins
        }
    }

    /// The raw secret keys backing this source — used by source validation and busy-detection
    /// fingerprinting.
    var secretKeys: [Data] {
        switch self {
        case let .externalAssetFromWallet(secretKey): [secretKey]
        case let .coinsFromPrivateKeys(secretKeys): secretKeys
        }
    }
}
