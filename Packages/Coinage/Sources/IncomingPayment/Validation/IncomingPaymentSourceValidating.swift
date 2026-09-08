import Foundation
import NovaCrypto

/// Validates incoming-payment source material and derives its busy-detection fingerprints.
///
/// A fingerprint is the sr25519 public key derived from a secret key — stable per key, so two
/// payments built from the same material share fingerprints and can be recognised as the same
/// source (`SourceBusy`). For the external-asset case the fingerprint is also the holder's accountId.
public protocol IncomingPaymentSourceValidating: Sendable {
    /// Validates every secret key in `source` can produce a keypair and returns their public keys.
    /// Throws `IncomingPaymentError.invalidSource` when the material is empty or malformed.
    func fingerprints(for source: IncomingPaymentSource) throws -> Set<Data>
}

/// Both source shapes carry sr25519 secret keys (coin keys and the wallet holder key alike), so one
/// implementation derives public keys for either. The protocol stays a seam for injection/mocking.
public final class IncomingPaymentSourceValidator: IncomingPaymentSourceValidating, @unchecked Sendable {
    private let snKeyFactory: any SNKeyFactoryProtocol

    public init(snKeyFactory: any SNKeyFactoryProtocol = SNKeyFactory()) {
        self.snKeyFactory = snKeyFactory
    }

    public func fingerprints(for source: IncomingPaymentSource) throws -> Set<Data> {
        let secretKeys = source.secretKeys
        let label = source.sourceType.rawValue

        guard !secretKeys.isEmpty else {
            throw IncomingPaymentError.invalidSource(reason: "No secret keys provided for \(label) source")
        }

        var fingerprints = Set<Data>()
        for secretKey in secretKeys {
            do {
                let publicKey = try snKeyFactory.createPublicKey(fromSecret: secretKey).rawData()
                fingerprints.insert(publicKey)
            } catch {
                throw IncomingPaymentError.invalidSource(
                    reason: "Malformed secret key for \(label) source: \(error.localizedDescription)"
                )
            }
        }
        return fingerprints
    }
}
