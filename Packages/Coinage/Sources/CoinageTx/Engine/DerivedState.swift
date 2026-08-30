import Foundation

/// Everything one entry evaluation needs, read once from a single pinned chain view.
///
/// Assembled by `RecoveryPass`; consumed by `RuleEvaluator`, which is pure over it.
public struct EntrySnapshot: Sendable {
    public let entry: CoinageTxEntry
    public let view: ChainView

    public let inputsAtFinalized: [ReadResult<AssetPresence>]
    public let inputsAtBest: [ReadResult<AssetPresence>]
    public let outputsAtFinalized: [ReadResult<AssetPresence>]
    public let outputsAtBest: [ReadResult<AssetPresence>]

    /// Per output, in `entry.outputs` order: true when nothing could have removed it —
    /// it carries no handoff mark and no entry other than this one consumes it.
    public let untouchedOutputs: [Bool]

    /// True when every input is a coin this wallet minted, never handed off, whose minting
    /// entry is `finalizedSuccess` with a closed mortality window.
    public let ownCoinInputs: Bool

    /// Canonical hash at `entry.successDetectedAt?.number`. Read only when that field is set.
    public let successBlockHash: ReadResult<Data>

    public init(
        entry: CoinageTxEntry,
        view: ChainView,
        inputsAtFinalized: [ReadResult<AssetPresence>],
        inputsAtBest: [ReadResult<AssetPresence>],
        outputsAtFinalized: [ReadResult<AssetPresence>],
        outputsAtBest: [ReadResult<AssetPresence>],
        untouchedOutputs: [Bool],
        ownCoinInputs: Bool,
        successBlockHash: ReadResult<Data> = .absent
    ) {
        self.entry = entry
        self.view = view
        self.inputsAtFinalized = inputsAtFinalized
        self.inputsAtBest = inputsAtBest
        self.outputsAtFinalized = outputsAtFinalized
        self.outputsAtBest = outputsAtBest
        self.untouchedOutputs = untouchedOutputs
        self.ownCoinInputs = ownCoinInputs
        self.successBlockHash = successBlockHash
    }
}

// MARK: - Predicates

/// Predicates the rules quantify over. Each is false under `failedRead`, so a read failure
/// never satisfies a rule and never produces a verdict.
public extension EntrySnapshot {
    /// The asset is on chain and, for a voucher, has not been unloaded — so it is still
    /// there to be spent.
    static func available(_ read: ReadResult<AssetPresence>) -> Bool {
        guard case let .present(presence) = read else { return false }
        return !presence.isUnloaded
    }

    /// The asset is not on chain at all.
    static func absent(_ read: ReadResult<AssetPresence>) -> Bool {
        read.isAbsent
    }

    /// The asset is on chain, whatever its alias state.
    static func exists(_ read: ReadResult<AssetPresence>) -> Bool {
        read.isPresent
    }

    /// A voucher present but marked unloaded — the marker a successful unload leaves behind.
    static func unloadedMarker(_ read: ReadResult<AssetPresence>) -> Bool {
        guard case let .present(presence) = read else { return false }
        return presence.isUnloaded
    }

    /// Execution is visible at this block: one of the entry's outputs is there, or one of its
    /// voucher inputs carries the unload marker.
    ///
    /// The marker matters for operations that mint nothing we can read — an unload into an
    /// external asset has no output at all, so the alias state is the only evidence.
    func executed(atFinalized: Bool) -> Bool {
        outputs(atFinalized: atFinalized).contains(where: Self.exists)
            || inputs(atFinalized: atFinalized).contains(where: Self.unloadedMarker)
    }

    /// The extrinsic can no longer be included.
    var windowClosed: Bool {
        entry.isWindowClosed(atFinalized: view.finalized.number)
    }

    /// Rule 7's search range: from the checkpoint up to the finalized head or the end of
    /// mortality, whichever comes first. `nil` when the finalized head is still below the
    /// checkpoint, which leaves nothing to search.
    var searchWindow: ClosedRange<UInt32>? {
        let upper = min(
            UInt64(entry.checkpoint.number) + UInt64(entry.mortality),
            UInt64(view.finalized.number)
        )
        guard upper >= UInt64(entry.checkpoint.number) else { return nil }
        return entry.checkpoint.number ... UInt32(upper)
    }

    /// An output that nothing could have removed is definitely absent at this block.
    func hasUntouchedAbsentOutput(atFinalized: Bool) -> Bool {
        zip(untouchedOutputs, outputs(atFinalized: atFinalized))
            .contains { $0 && Self.absent($1) }
    }

    /// An input is definitely still there to be spent at this block.
    func hasAvailableInput(atFinalized: Bool) -> Bool {
        inputs(atFinalized: atFinalized).contains(where: Self.available)
    }

    /// Every input read cleanly and every one is gone at this block.
    func allInputsAbsent(atFinalized: Bool) -> Bool {
        inputs(atFinalized: atFinalized).allAbsent()
    }

    func hasExistingInput(atFinalized: Bool) -> Bool {
        inputs(atFinalized: atFinalized).contains(where: Self.exists)
    }

    /// CoinageTxInput reads at the finalized or the best head.
    func inputs(atFinalized: Bool) -> [ReadResult<AssetPresence>] {
        atFinalized ? inputsAtFinalized : inputsAtBest
    }

    /// Output reads at the finalized or the best head.
    func outputs(atFinalized: Bool) -> [ReadResult<AssetPresence>] {
        atFinalized ? outputsAtFinalized : outputsAtBest
    }
}
