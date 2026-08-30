import Foundation

/// Validates registration invariants directly against the store transaction, keyed by public key.
///
/// Every asset resolves to its on-chain public key — an own coin/voucher from its index, a received
/// coin from the key itself — so the four checks compare one key space, matching the store's
/// ``CoinageTxValidationContext``. The offending key is mapped back to its asset for the error.
public struct RegistrationValidator {
    private let coinKeyDeriver: any CoinKeyDeriving
    private let voucherKeyDeriver: any VoucherKeyDeriving

    public init(coinKeyDeriver: any CoinKeyDeriving, voucherKeyDeriver: any VoucherKeyDeriving) {
        self.coinKeyDeriver = coinKeyDeriver
        self.voucherKeyDeriver = voucherKeyDeriver
    }

    /// Validates the registration invariants, in order:
    /// 1. Non-empty entry (consumes or mints something)
    /// 2. Fresh outputs — not minted by another entry, and not a key received from a peer
    /// 3. Unique consumer — no input already claimed by a non-failure entry
    /// 4. Blocked handoff — no input carrying a handoff mark
    public func validate(_ entry: DurabilityEntry, transaction: CoinageTxValidationContext) throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw DurabilityError.emptyEntry
        }

        let outputsByKey = try publicKeys(ofOutputs: entry.outputs)
        let inputsByKey = try publicKeys(ofInputs: entry.inputs)
        let outputKeys = Set(outputsByKey.keys)
        let inputKeys = Set(inputsByKey.keys)

        if let key = try transaction.filterMinted(outputKeys).first, let output = outputsByKey[key] {
            throw DurabilityError.outputNotFresh(output.identifier)
        }
        if let key = try transaction.filterReceived(outputKeys).first, let output = outputsByKey[key] {
            throw DurabilityError.outputNotFresh(output.identifier)
        }

        if let key = try transaction.filterClaimed(inputKeys).first, let input = inputsByKey[key] {
            throw DurabilityError.inputAlreadyClaimed(input.identifier)
        }

        if let key = try transaction.filterHandedOff(inputKeys).first, let input = inputsByKey[key] {
            throw DurabilityError.inputHandedOff(input.identifier)
        }
    }

    private func publicKeys(ofOutputs outputs: [OwnAsset]) throws -> [PublicKey: OwnAsset] {
        var result: [PublicKey: OwnAsset] = [:]
        for output in outputs {
            try result[publicKey(of: output)] = output
        }
        return result
    }

    private func publicKeys(ofInputs inputs: [DurabilityInput]) throws -> [PublicKey: DurabilityInput] {
        var result: [PublicKey: DurabilityInput] = [:]
        for input in inputs {
            let key: PublicKey =
                switch input {
                case let .coin(.own(index)): try coinKeyDeriver.derivePublicKey(index: index)
                case let .coin(.received(publicKey)): publicKey
                case let .recyclerVoucher(index): try voucherKeyDeriver.derivePublicKey(index: index)
                }
            result[key] = input
        }
        return result
    }

    private func publicKey(of asset: OwnAsset) throws -> PublicKey {
        switch asset {
        case let .coin(index): try coinKeyDeriver.derivePublicKey(index: index)
        case let .recyclerVoucher(index): try voucherKeyDeriver.derivePublicKey(index: index)
        }
    }
}
