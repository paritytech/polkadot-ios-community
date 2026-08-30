import Foundation

/// Validates registration invariants directly against the store transaction.
///
/// It needs the coin key deriver to turn an output coin's derivation index into the on-chain
/// public key the Fresh-outputs check compares against keys received from peers.
public struct RegistrationValidator {
    private let coinKeyDeriver: any CoinKeyDeriving

    public init(coinKeyDeriver: any CoinKeyDeriving) {
        self.coinKeyDeriver = coinKeyDeriver
    }

    /// Validates the registration invariants, in order:
    /// 1. Non-empty entry (consumes or mints something)
    /// 2. Fresh outputs — not minted by another entry, and not a key received from a peer
    /// 3. Unique consumer — no input already claimed by a non-failure entry
    /// 4. Blocked handoff — no input carrying a handoff mark
    public func validate(_ entry: DurabilityEntry, transaction: CoinageStoreTransaction) throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw DurabilityError.emptyEntry
        }

        if let duplicate = try transaction.mintedOutput(among: Set(entry.outputs)).first {
            throw DurabilityError.outputNotFresh(duplicate.identifier)
        }

        let outputsByKey = try publicKeysByOutput(of: entry.outputs)
        let colliding = try transaction.receivedInputPublicKeys(among: Set(outputsByKey.keys))
        if let key = colliding.first, let output = outputsByKey[key] {
            throw DurabilityError.outputNotFresh(output.identifier)
        }

        if let claimed = try transaction.claimedInputs(among: Set(entry.inputs)).first {
            throw DurabilityError.inputAlreadyClaimed(claimed.identifier)
        }

        if let marked = try transaction.handedOff(among: Set(entry.inputs)).first {
            throw DurabilityError.inputHandedOff(marked.identifier)
        }
    }

    /// The on-chain public key of each coin output, keyed by that key. Vouchers have no such
    /// address, so they are skipped.
    private func publicKeysByOutput(of outputs: [DurabilityOutput]) throws -> [Data: DurabilityOutput] {
        var result: [Data: DurabilityOutput] = [:]
        for output in outputs {
            guard case let .coin(index) = output else { continue }
            let publicKey = try coinKeyDeriver.derivePublicKey(index: index)
            result[publicKey] = output
        }
        return result
    }
}
