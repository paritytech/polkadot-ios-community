import Coinage
import Foundation
import Testing

@Suite("RuleEvaluator")
struct RuleEvaluatorTests {
    // MARK: - Snapshot Builder

    /// Creates an ``EntrySnapshot`` with sensible defaults, parameterised for test variation.
    /// All reads default to `.absent`; checkpoint is block 100; mortality is 64 blocks.
    private func makeSnapshot(
        checkpointNumber: UInt32 = 100,
        mortality: UInt32 = 64,
        finalizedNumber: UInt32 = 160,
        bestNumber: UInt32 = 170,
        inputsAtFinalized: [ReadResult<AssetPresence>]? = nil,
        inputsAtBest: [ReadResult<AssetPresence>]? = nil,
        outputsAtFinalized: [ReadResult<AssetPresence>]? = nil,
        outputsAtBest: [ReadResult<AssetPresence>]? = nil,
        untouchedOutputs: [Bool] = [true],
        ownCoinInputs: Bool = false,
        successDetectedAt: BlockRef? = nil,
        successBlockHash: ReadResult<Data> = .absent
    ) -> EntrySnapshot {
        let defaultReads = [ReadResult<AssetPresence>.absent]

        let entry = DurabilityEntry(
            inputs: [.coin(.own(0))],
            outputs: [.coin(0)],
            checkpoint: BlockRef(number: checkpointNumber, hash: Data([UInt8(checkpointNumber)])),
            mortality: mortality,
            successDetectedAt: successDetectedAt
        )

        let view = ChainView(
            finalized: BlockRef(number: finalizedNumber, hash: Data([UInt8(finalizedNumber)])),
            best: BlockRef(number: bestNumber, hash: Data([UInt8(bestNumber)]))
        )

        return EntrySnapshot(
            entry: entry,
            view: view,
            inputsAtFinalized: inputsAtFinalized ?? defaultReads,
            inputsAtBest: inputsAtBest ?? defaultReads,
            outputsAtFinalized: outputsAtFinalized ?? defaultReads,
            outputsAtBest: outputsAtBest ?? defaultReads,
            untouchedOutputs: untouchedOutputs,
            ownCoinInputs: ownCoinInputs,
            successBlockHash: successBlockHash
        )
    }

    // MARK: - Rule 0 (Recorded Inclusion)

    @Test("Rule 0: successDetectedAt set, hash present and matching, block ≤ finalized")
    func rule0_RecordedSuccessAtFinalized() {
        let detectedBlock = BlockRef(number: 150, hash: Data([150]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            successDetectedAt: detectedBlock,
            successBlockHash: .present(Data([150]))
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.finalizedSuccess))
    }

    @Test("Rule 0: successDetectedAt set, hash present and matching, block > finalized")
    func rule0_RecordedSuccessAtBest() {
        let detectedBlock = BlockRef(number: 165, hash: Data([165]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            successDetectedAt: detectedBlock,
            successBlockHash: .present(Data([165]))
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.pendingSuccess))
    }

    @Test("Rule 0: hash present but different (reorged out), no execution at best")
    func rule0_ReorgedOutNoExecution() {
        let detectedBlock = BlockRef(number: 150, hash: Data([150]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            inputsAtBest: [.absent],
            outputsAtBest: [.absent],
            successDetectedAt: detectedBlock,
            successBlockHash: .present(Data([99])) // Different hash
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .clearSuccessAndSetPending)
    }

    @Test("Rule 0: hash present but different, output exists at best")
    func rule0_ReorgedOutWithExecution() {
        let detectedBlock = BlockRef(number: 150, hash: Data([150]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            outputsAtBest: [.present(AssetPresence(isUnloaded: false))],
            successDetectedAt: detectedBlock,
            successBlockHash: .present(Data([99])) // Different hash
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .statusRecordingSuccess(.pendingSuccess, snapshot.view.best))
    }

    @Test("Rule 0: hash failedRead (record kept, abort)")
    func rule0_HashFailedRead() {
        let detectedBlock = BlockRef(number: 150, hash: Data([150]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            successDetectedAt: detectedBlock,
            successBlockHash: .failedRead
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .abort)
    }

    @Test("Rule 0: no successDetectedAt, falls through to Rule 1")
    func rule0_NoRecordFallsThrough() {
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            bestNumber: 170,
            outputsAtFinalized: [.present(AssetPresence(isUnloaded: false))],
            successDetectedAt: nil
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rule 1 fires: output present at finalized
        #expect(verdict == .status(.finalizedSuccess))
    }

    // MARK: - Rules 1 / 2 (Execution Visible)

    @Test("Rule 1: output present at finalized")
    func rule1_ExecutionAtFinalized() {
        let snapshot = makeSnapshot(
            outputsAtFinalized: [.present(AssetPresence(isUnloaded: false))]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.finalizedSuccess))
    }

    @Test("Rule 1: voucher input unloaded at finalized (execution marker)")
    func rule1_VoucherUnloadMarkerAtFinalized() {
        let snapshot = makeSnapshot(
            inputsAtFinalized: [.present(AssetPresence(isUnloaded: true))],
            outputsAtFinalized: [.absent]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.finalizedSuccess))
    }

    @Test("Rule 2: output present at best only")
    func rule2_ExecutionAtBest() {
        let snapshot = makeSnapshot(
            outputsAtFinalized: [.absent],
            outputsAtBest: [.present(AssetPresence(isUnloaded: false))]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .statusRecordingSuccess(.pendingSuccess, snapshot.view.best))
    }

    // MARK: - Rules 3 / 4 (Window Closed)

    @Test("Rule 3: window closed, untouched output absent at finalized → failure")
    func rule3_WindowClosedUntouchedAbsent() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165, // Window closed: 165 > 100 + 64
            outputsAtFinalized: [.absent],
            untouchedOutputs: [true]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.failure))
    }

    @Test("Rule 4: window closed, available input at finalized → failure")
    func rule4_WindowClosedAvailableInput() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165,
            inputsAtFinalized: [.present(AssetPresence(isUnloaded: false))],
            outputsAtFinalized: [.absent],
            untouchedOutputs: [false]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.failure))
    }

    @Test("Rule 3/4 short-circuit: window NOT closed, untouched absent at finalized")
    func rule3_WindowOpenUntouchedAbsent() {
        let snapshot = makeSnapshot(
            finalizedNumber: 160, // Window open: 160 <= 100 + 64
            outputsAtFinalized: [.absent],
            untouchedOutputs: [true]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rules 3/4 do not fire, falls to 3b/4b
        #expect(verdict != .status(.failure))
    }

    @Test("Rule 3 does not fire: output absent but untouchedOutputs false")
    func rule3_UntouchedFalse() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165,
            outputsAtFinalized: [.absent],
            untouchedOutputs: [false]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rule 3 condition not met; falls through to Rule 5/6/3b/4b
        #expect(verdict != .status(.failure))
    }

    // MARK: - Rules 5 / 6 (ownCoinInputs)

    @Test("Rule 5: ownCoinInputs true, all inputs absent at finalized")
    func rule5_OwnCoinsAllAbsent() {
        let snapshot = makeSnapshot(
            inputsAtFinalized: [.absent],
            ownCoinInputs: true
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.finalizedSuccess))
    }

    @Test("Rule 5 does not fire: ownCoinInputs false")
    func rule5_NoOwnCoinInputs() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165, // Window closed so 3b/4b don't apply
            inputsAtFinalized: [.absent],
            outputsAtFinalized: [.absent],
            untouchedOutputs: [false], // Rule 3 doesn't fire (not untouched)
            ownCoinInputs: false
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // ownCoinInputs false, so Rule 5 does not fire; Rule 3/4 also don't fire
        #expect(verdict == .searchBodies)
    }

    @Test("Rule 6: ownCoinInputs true, input at finalized, all absent at best")
    func rule6_OwnCoinsInputAtFinalizedAbsentAtBest() {
        let snapshot = makeSnapshot(
            inputsAtFinalized: [.present(AssetPresence(isUnloaded: false))],
            inputsAtBest: [.absent],
            ownCoinInputs: true
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.pendingSuccess))
    }

    // MARK: - Rules 3b / 4b (Pre-Mortality Short Circuit)

    @Test("Rule 3b: window open, untouched output absent at best → pending")
    func rule3b_WindowOpenUntouchedAbsentAtBest() {
        let snapshot = makeSnapshot(
            finalizedNumber: 160, // Window open
            outputsAtBest: [.absent],
            untouchedOutputs: [true]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.pending))
    }

    @Test("Rule 4b: window open, available input at best → pending")
    func rule4b_WindowOpenAvailableInputAtBest() {
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            inputsAtBest: [.present(AssetPresence(isUnloaded: false))],
            untouchedOutputs: [false]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        #expect(verdict == .status(.pending))
    }

    @Test("Rule 3b/4b short-circuit: window closed same reads do not apply")
    func rule3b4b_WindowClosedNoShortCircuit() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165, // Window closed
            inputsAtFinalized: [.failedRead], // Rule 4 can't fire
            inputsAtBest: [.present(AssetPresence(isUnloaded: false))],
            outputsAtFinalized: [.failedRead], // Rule 3 can't fire
            outputsAtBest: [.absent],
            untouchedOutputs: [true]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rules 3b/4b short circuit only when window open; here window closed,
        // Rules 3/4 don't fire (failedRead), so searchBodies
        #expect(verdict == .searchBodies)
    }

    // MARK: - failedRead Never Decides

    @Test("failedRead window closed: output failedRead, untouched true ≠ failure")
    func failedRead_WindowClosedUntouchedNotFailure() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165,
            outputsAtFinalized: [.failedRead],
            untouchedOutputs: [true]
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // failedRead aborts, not failure
        #expect(verdict != .status(.failure))
    }

    @Test("failedRead: ownCoinInputs true, inputs [failedRead, absent] ≠ finalizedSuccess")
    func failedRead_OwnCoinsNotAllAbsent() {
        let snapshot = makeSnapshot(
            inputsAtFinalized: [.failedRead, .absent],
            ownCoinInputs: true
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // allAbsent() must be false when any failedRead; Rule 5 doesn't fire
        #expect(verdict != .status(.finalizedSuccess))
    }

    // MARK: - Rule 7 Mapping (verdict(forSearch:windowClosed:))

    @Test("Rule 7: foundSucceeded → finalizedSuccess; foundFailed → failure; unreadable → pending")
    func rule7_SearchOutcomeMappings() {
        let evaluator = RuleEvaluator()

        let resultSucceeded = evaluator.verdict(
            forSearch: .foundSucceeded(BlockRef(number: 150, hash: Data([150]))),
            windowClosed: true
        )
        #expect(resultSucceeded == .status(.finalizedSuccess))

        let resultFailed = evaluator.verdict(
            forSearch: .foundFailed(BlockRef(number: 150, hash: Data([150]))),
            windowClosed: true
        )
        #expect(resultFailed == .status(.failure))

        let resultUnreadable = evaluator.verdict(
            forSearch: .foundOutcomeUnreadable(BlockRef(number: 150, hash: Data([150]))),
            windowClosed: true
        )
        #expect(resultUnreadable == .status(.pending))
    }

    @Test("Rule 7: notFoundWindowComplete, windowClosed: true → failure")
    func rule7_NotFoundWindowCompleteWindowClosed() {
        let evaluator = RuleEvaluator()
        let verdict = evaluator.verdict(forSearch: .notFoundWindowComplete, windowClosed: true)

        #expect(verdict == .status(.failure))
    }

    @Test("Rule 7: notFoundWindowComplete, windowClosed: false → pending")
    func rule7_NotFoundWindowOpenWindowNotClosed() {
        let evaluator = RuleEvaluator()
        let verdict = evaluator.verdict(forSearch: .notFoundWindowComplete, windowClosed: false)

        #expect(verdict == .status(.pending))
    }

    @Test("Rule 7: incomplete → pending regardless of windowClosed")
    func rule7_IncompleteRegardlessWindow() {
        let evaluator = RuleEvaluator()

        let resultWindowClosed = evaluator.verdict(forSearch: .incomplete, windowClosed: true)
        #expect(resultWindowClosed == .status(.pending))

        let resultWindowOpen = evaluator.verdict(forSearch: .incomplete, windowClosed: false)
        #expect(resultWindowOpen == .status(.pending))
    }

    // MARK: - Rule Ordering

    @Test("Rule 3 beats Rule 5: window closed, ownCoinInputs true, untouched absent")
    func ordering_Rule3BeatsRule5() {
        let snapshot = makeSnapshot(
            finalizedNumber: 165, // Window closed
            inputsAtFinalized: [.absent],
            outputsAtFinalized: [.absent],
            untouchedOutputs: [true],
            ownCoinInputs: true
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rule 3 fires first and decides failure (documented spec defect: ordering
        // creates ambiguity when an output vanishes after successful handoff)
        #expect(verdict == .status(.failure))
    }

    @Test("Rule 0 beats Rule 1: stale hash + execution at finalized uses Rule 0")
    func ordering_Rule0BeatsRule1() {
        let detectedBlock = BlockRef(number: 150, hash: Data([150]))
        let snapshot = makeSnapshot(
            finalizedNumber: 160,
            outputsAtFinalized: [.present(AssetPresence(isUnloaded: false))],
            outputsAtBest: [.present(AssetPresence(isUnloaded: false))],
            successDetectedAt: detectedBlock,
            successBlockHash: .present(Data([99])) // Different hash
        )

        let evaluator = RuleEvaluator()
        let verdict = evaluator.evaluate(snapshot)

        // Rule 0 fires and clears the stale record + records pending at best
        // rather than Rule 1's finalizedSuccess
        #expect(verdict == .statusRecordingSuccess(.pendingSuccess, snapshot.view.best))
    }
}
