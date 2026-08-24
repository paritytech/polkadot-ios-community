import Foundation

/// Set queries over a group of entries, keyed by ``OwnAsset/identifier``.
///
/// The reconciler, the recovery pass, the derived asset status and the store's registration
/// check all ask the same question in different words: which assets are named by entries whose
/// status satisfies some predicate. Answering it in one place keeps those answers from drifting
/// apart.
public extension Sequence<DurabilityEntry> {
    /// Identifiers of the inputs of every entry whose status matches.
    func inputIdentifiers(where matches: (EntryStatus) -> Bool = { _ in true }) -> Set<String> {
        Set(filter { matches($0.status) }.flatMap { $0.inputs.map(\.identifier) })
    }

    /// Identifiers of the outputs of every entry whose status matches.
    func outputIdentifiers(where matches: (EntryStatus) -> Bool = { _ in true }) -> Set<String> {
        Set(filter { matches($0.status) }.flatMap { $0.outputs.map(\.identifier) })
    }

    /// Identifiers of both the inputs and the outputs of every entry whose status matches.
    func assetIdentifiers(where matches: (EntryStatus) -> Bool = { _ in true }) -> Set<String> {
        inputIdentifiers(where: matches).union(outputIdentifiers(where: matches))
    }

    /// The entry that minted each output, keyed by ``OwnAsset/identifier``.
    ///
    /// Built once per caller rather than searched per asset: the recovery pass and the derived
    /// asset status both ask "which entry minted this?" for every asset they hold.
    func mintersByOutputIdentifier() -> [String: DurabilityEntry] {
        reduce(into: [:]) { index, entry in
            for output in entry.outputs {
                index[output.identifier] = entry
            }
        }
    }
}
