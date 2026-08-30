import Foundation
import SubstrateSdk

/// Validates registration invariants directly against the store transaction, keyed by public key.
///
/// Every asset already carries its on-chain public key, so the four checks compare one key space,
/// matching the store's ``CoinageTxValidationContext``. The offending key is reported in the error.
public struct CoinageTxRegistrationValidator {
    public init() {}

    /// Validates the registration invariants, in order:
    /// 1. Non-empty entry (consumes or mints something)
    /// 2. Fresh outputs — not minted by another entry, and not a key received from a peer
    /// 3. Unique consumer — no input already claimed by a non-failure entry
    /// 4. Blocked handoff — no input carrying a handoff mark
    public func validate(_ entry: CoinageTxEntry, transaction: CoinageTxValidationContext) throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw CoinageTxError.emptyEntry
        }

        let outputKeys = Set(entry.outputs.map(\.publicKey))
        let inputKeys = Set(entry.inputs.map(\.publicKey))

        if let key = try transaction.filterMinted(outputKeys).first {
            throw CoinageTxError.outputNotFresh(key.toHex())
        }
        if let key = try transaction.filterReceived(outputKeys).first {
            throw CoinageTxError.outputNotFresh(key.toHex())
        }
        if let key = try transaction.filterClaimed(inputKeys).first {
            throw CoinageTxError.inputAlreadyClaimed(key.toHex())
        }
        if let key = try transaction.filterHandedOff(inputKeys).first {
            throw CoinageTxError.inputHandedOff(key.toHex())
        }
    }
}
