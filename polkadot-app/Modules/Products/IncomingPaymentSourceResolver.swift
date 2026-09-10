import Coinage
import Foundation
import KeyDerivation
import Products

/// Resolves a stored source descriptor into signing/claim material. Product-account indices are
/// re-derived from the device root entropy here — the Coinage package cannot. Resolution throws on
/// malformed key material, which surfaces as `IncomingPaymentError.invalidSource`.
final class IncomingPaymentSourceResolver: IncomingPaymentSourceResolving, @unchecked Sendable {
    private let entropyManager: RootEntropyManaging

    init(entropyManager: RootEntropyManaging = RootEntropyManager.shared) {
        self.entropyManager = entropyManager
    }

    func resolve(
        productId: String,
        descriptor: IncomingPaymentSourceDescriptor
    ) async throws -> ResolvedIncomingSource {
        switch descriptor {
        case let .productAccount(indexData):
            let selector = try JSONDecoder().decode(ProductAccountSelector.self, from: indexData)
            let accountId = ProductAccountId(productId: productId, derivationIndex: selector)
            let wallet = try DynamicDerivedWallet(
                derivationPath: accountId.derivationPath(),
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
