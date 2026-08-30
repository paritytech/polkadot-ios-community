import Foundation

/// The live and terminal entries of one pass, indexed for O(1) provenance lookups.
///
/// Built once per pass from `getAllEntries` + the handoff marks, so the rules and propagation query
/// precomputed maps instead of re-scanning every entry. Keyed by each asset's stable identifier.
/// Mirrors Android's `CoinageEntryDag`.
public struct CoinageEntryDag: Sendable {
    public let entries: [CoinageTxEntry]
    private let handedOff: Set<String>
    private let minterByKey: [String: CoinageTxEntry]
    private let consumersByKey: [String: [CoinageTxEntry]]

    public init(entries: [CoinageTxEntry], handedOff: Set<String>) {
        self.entries = entries
        self.handedOff = handedOff

        var minters: [String: CoinageTxEntry] = [:]
        var consumers: [String: [CoinageTxEntry]] = [:]
        for entry in entries {
            for output in entry.outputs {
                minters[output.identifier] = entry
            }
            for input in entry.inputs {
                consumers[input.identifier, default: []].append(entry)
            }
        }
        minterByKey = minters
        consumersByKey = consumers
    }

    /// The entry that minted the asset with this identifier, if any.
    public func minter(_ key: String) -> CoinageTxEntry? {
        minterByKey[key]
    }

    /// Every entry consuming the asset with this identifier, including terminal ones.
    public func consumers(_ key: String) -> [CoinageTxEntry] {
        consumersByKey[key] ?? []
    }

    /// Every entry that consumes one of `entry`'s outputs.
    public func successors(_ entry: CoinageTxEntry) -> [CoinageTxEntry] {
        var seen: Set<CoinageTxId> = []
        var result: [CoinageTxEntry] = []
        for output in entry.outputs {
            for consumer in consumers(output.identifier) where seen.insert(consumer.id).inserted {
                result.append(consumer)
            }
        }
        return result
    }

    public func isHandedOff(_ key: String) -> Bool {
        handedOff.contains(key)
    }
}
