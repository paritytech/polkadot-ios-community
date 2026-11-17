import Foundation
import SubstrateSdk
import KeyDerivation

public enum SlotHolderSignerError: Error, Equatable {
    case accountMismatch(signerKeyId: String)
}

/// Resolves the signer of a statement account from the key reference stored with its allowance row,
/// so an occupied slot can be handed over with the holder's signature.
public protocol SlotHolderSignerResolving {
    func signer(for signerKeyId: String, expecting accountId: AccountId) throws -> any TypedSigningProviding
}
