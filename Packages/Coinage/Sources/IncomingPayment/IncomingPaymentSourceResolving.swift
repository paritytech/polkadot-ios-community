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

public final class IncomingPaymentSourceResolver: IncomingPaymentSourceResolving, @unchecked Sendable {
    private let entropyManager: RootEntropyManaging

    public init(entropyManager: RootEntropyManaging) {
        self.entropyManager = entropyManager
    }

    public func resolve(
        productId _: String,
        descriptor: IncomingPaymentSourceDescriptor
    ) async throws -> ResolvedIncomingSource {
        switch descriptor {
        case let .productAccount(derivationPath):
            let wallet = DynamicDerivedWallet(
                derivationPath: derivationPath,
                entropyManager: entropyManager
            )
            _ = try wallet.getRawPublicKey()
            return .wallet(wallet)

        case let .privateKey(secretKey):
            let wallet = DynamicDerivedWallet(secretKeyProvider: { secretKey })
            _ = try wallet.getRawPublicKey()
            return .wallet(wallet)

        case let .coins(secretKeys):
            return .coins(secretKeys: secretKeys)
        }
    }
}
