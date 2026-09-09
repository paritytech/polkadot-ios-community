import Foundation
import KeyDerivation

/// A resolved source ready to sign or be claimed. Rebuilt from the descriptor on each run, so a
/// resumed top-up produces exactly the keypairs the first attempt would have.
public enum ResolvedIncomingSource {
    /// An external-asset holder to onboard vouchers from (product-account or private-key sources).
    case wallet(any WalletManaging)
    /// Bearer coin secret keys to claim (coins source).
    case coins(secretKeys: [Data])
}

/// Turns a stored source descriptor into signing/claim material.
///
/// Implemented app-side because resolving a product-account index needs the device root entropy the
/// Coinage package does not hold. Throwing resolution is how an invalid source surfaces
/// (`IncomingPaymentError.invalidSource`).
public protocol IncomingPaymentSourceResolving: Sendable {
    func resolve(
        productId: String,
        descriptor: IncomingPaymentSourceDescriptor
    ) async throws -> ResolvedIncomingSource
}
