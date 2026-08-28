import Foundation
import SDKLogger

/// One bounded sweep over the live entry set.
///
/// Pins a single chain view, repairs the projection, then evaluates every live entry that no
/// submission currently owns, in registration order, and returns. It is never awaited by
/// startup: a single unresolvable entry must not hold the app for a mortality window.
///
/// Triggered on launch, on a new finalized head, on connectivity return, on process resume,
/// and on watcher release.
actor RecoveryPass {
    private let store: any DurabilityStoring
    private let chain: any DurabilityChainReading
    private let watched: WatchedEntrySet
    private let transaction: StatusUpdateTransaction
    private let evaluator = RuleEvaluator()
    private let logger: SDKLoggerProtocol?

    private var isRunning = false
    private var rerunRequested = false

    private static let maxCoalescedPasses = 2

    init(
        store: any DurabilityStoring,
        chain: any DurabilityChainReading,
        watched: WatchedEntrySet,
        transaction: StatusUpdateTransaction,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.chain = chain
        self.watched = watched
        self.transaction = transaction
        self.logger = logger
    }

    /// Runs one pass. At most one runs at a time; a request arriving during a pass causes
    /// one additional pass afterwards rather than being dropped. The rerun count is capped
    /// to prevent unbounded spinning if triggers keep arriving faster than passes complete.
    func run() async {
        guard !isRunning else {
            rerunRequested = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        var iterations = 0
        repeat {
            // Must reset rerunRequested before performPass(), not after: a request arriving
            // mid-pass would be swallowed if we reset after. This recreates the original bug.
            rerunRequested = false
            do {
                try await performPass()
            } catch {
                logger?.error("Recovery pass failed: \(error)")
            }
            iterations += 1
        } while rerunRequested && iterations < Self.maxCoalescedPasses
    }
}

// MARK: - Pass

private extension RecoveryPass {
    func performPass() async throws {
        let view = try await chain.pinChainView()

        let allEntries = try await store.fetchAll()
        let handedOff = try await store.handedOffIdentifiers()
        let live = allEntries.filter(\.status.isLive)

        for entry in live {
            // Read per entry rather than once for the pass: an entry registered after the
            // pass started is owned by its submission and must get no verdict from a view
            // that predates it.
            guard !watched.isWatched(entry.id) else { continue }

            guard await chain.isCurrent(view) else {
                throw DurabilityError.connectionReplaced
            }

            let snapshot = await makeSnapshot(
                for: entry,
                view: view,
                allEntries: allEntries,
                handedOff: handedOff
            )
            try await decide(snapshot)
        }

        try await propagate()
    }

    func decide(_ snapshot: EntrySnapshot) async throws {
        let verdict = evaluator.evaluate(snapshot)
        guard case .searchBodies = verdict else {
            try await transaction.apply(verdict, to: snapshot.entry.id, observedStatus: snapshot.entry.status)
            return
        }

        guard let txHash = snapshot.entry.txHash, let window = snapshot.searchWindow else {
            // No hash means the extrinsic was never broadcast, so there is nothing to find.
            // Once the window has closed it can never execute.
            let fallback: RuleVerdict = snapshot.windowClosed
                ? .status(.failure)
                : .status(.pending)
            try await transaction.apply(fallback, to: snapshot.entry.id, observedStatus: snapshot.entry.status)
            return
        }

        let outcome = await chain.searchBodies(for: txHash, in: window)
        let verdictFromSearch = evaluator.verdict(
            forSearch: outcome,
            windowClosed: snapshot.windowClosed
        )
        try await transaction.apply(verdictFromSearch, to: snapshot.entry.id, observedStatus: snapshot.entry.status)
    }

    /// A live entry whose output a finalized entry consumed must itself have executed.
    ///
    /// Known spec defect: this promotes one link per pass, because it reads the entry set
    /// once rather than iterating to a fixed point. A chain of three converges over
    /// successive passes rather than in a single one.
    func propagate() async throws {
        let entries = try await store.fetchAll()
        let consumedByFinalized = entries.inputIdentifiers { $0 == .finalizedSuccess }
        guard !consumedByFinalized.isEmpty else { return }

        for entry in entries where entry.status.isLive && !watched.isWatched(entry.id) {
            guard entry.outputs.contains(where: { consumedByFinalized.contains($0.identifier) })
            else { continue }
            try await transaction.apply(.status(.finalizedSuccess), to: entry.id, observedStatus: entry.status)
        }
    }
}

// MARK: - Snapshot

private extension RecoveryPass {
    func makeSnapshot(
        for entry: DurabilityEntry,
        view: ChainView,
        allEntries: [DurabilityEntry],
        handedOff: Set<String>
    ) async -> EntrySnapshot {
        async let inputsAtFinalized = chain.readInputs(entry.inputs, at: view.finalized)
        async let inputsAtBest = chain.readInputs(entry.inputs, at: view.best)
        async let outputsAtFinalized = chain.readOutputs(entry.outputs, at: view.finalized)
        async let outputsAtBest = chain.readOutputs(entry.outputs, at: view.best)

        let successBlockHash: ReadResult<Data> =
            if let detected = entry.successDetectedAt {
                await chain.blockHash(at: detected.number)
            } else {
                .absent
            }

        return await EntrySnapshot(
            entry: entry,
            view: view,
            inputsAtFinalized: inputsAtFinalized,
            inputsAtBest: inputsAtBest,
            outputsAtFinalized: outputsAtFinalized,
            outputsAtBest: outputsAtBest,
            untouchedOutputs: Self.untouchedFlags(
                for: entry,
                allEntries: allEntries,
                handedOff: handedOff
            ),
            ownCoinInputs: Self.ownCoinInputs(
                for: entry,
                allEntries: allEntries,
                handedOff: handedOff,
                view: view
            ),
            successBlockHash: successBlockHash
        )
    }

    /// An output is untouched when nothing could have removed it: it carries no handoff mark
    /// and no entry but this one claims it.
    ///
    /// Rule 3 turns an untouched absent output into a FAILURE, so a missing handoff mark here
    /// is what would fail a successful entry.
    static func untouchedFlags(
        for entry: DurabilityEntry,
        allEntries: [DurabilityEntry],
        handedOff: Set<String>
    ) -> [Bool] {
        entry.outputs.map { output in
            let identifier = output.identifier
            guard !handedOff.contains(identifier) else { return false }
            return !allEntries.contains { other in
                other.id != entry.id
                    && other.status != .failure
                    && other.inputs.contains { $0.identifier == identifier }
            }
        }
    }

    /// Every input is a coin this wallet minted, never handed off, whose minter finalized
    /// and whose minter's window has closed.
    ///
    /// This is what makes absence mean something. A coin also reads absent before it was
    /// ever minted, so absence alone decides nothing; a finalized minter proves the coin
    /// existed, and a closed minter window proves enough time has passed for it to still be
    /// visible had nothing taken it.
    static func ownCoinInputs(
        for entry: DurabilityEntry,
        allEntries: [DurabilityEntry],
        handedOff: Set<String>,
        view: ChainView
    ) -> Bool {
        guard !entry.inputs.isEmpty else { return false }

        let mintersByOutput = allEntries.mintersByOutputIdentifier()

        return entry.inputs.allSatisfy { input in
            guard case .coin(.own) = input, !handedOff.contains(input.identifier) else {
                return false
            }
            guard let minter = mintersByOutput[input.identifier],
                  minter.status == .finalizedSuccess
            else { return false }
            return minter.isWindowClosed(atFinalized: view.finalized.number)
        }
    }
}
