import Foundation

/// Product-supplied, opaque idempotency key for a top-up (the hex of the wire `[u8;32]`).
public typealias IncomingPaymentId = String

/// What a top-up draws its funds from, as the persisted bytes rather than anything resolved.
///
/// Held in the encrypted secret store (never the DB); a wallet or coin keypairs are rebuilt from it on
/// each run, so a resumed top-up signs exactly as the first attempt would have. A product-account
/// source stores only the derivation **index** — never a derived secret key — so the most it holds at
/// rest is an index that is useless without the device root entropy.
public enum IncomingPaymentSourceDescriptor: Equatable, Sendable {
    case productAccount(indexData: Data)
    case privateKey(secretKey: Data)
    case coins(secretKeys: [Data])
}

/// Persisted discriminator for a descriptor (the tag the secret store serialises alongside the bytes).
public enum IncomingPaymentSourceKind: String, Sendable, Equatable {
    case productAccount
    case privateKey
    case coins
}

public extension IncomingPaymentSourceDescriptor {
    var kind: IncomingPaymentSourceKind {
        switch self {
        case .productAccount: .productAccount
        case .privateKey: .privateKey
        case .coins: .coins
        }
    }

    /// Whether two sources are the same money and so cannot be claimed at once.
    ///
    /// A derivation index means nothing outside the product whose subtree it indexes, so two of those
    /// are the same source only when the product is too. A private key is the same only as itself.
    /// Coin keys are the money rather than a way to reach it, so a single key in common is enough —
    /// both top-ups would submit a claim for that coin and one would be refused.
    func drawsOnSameFunds(as other: IncomingPaymentSourceDescriptor, sameProduct: Bool) -> Bool {
        switch (self, other) {
        case let (.productAccount(lhs), .productAccount(rhs)):
            sameProduct && lhs == rhs
        case let (.privateKey(lhs), .privateKey(rhs)):
            lhs == rhs
        case let (.coins(lhs), .coins(rhs)):
            !Set(lhs).isDisjoint(with: Set(rhs))
        default:
            false
        }
    }
}
