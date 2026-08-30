import Foundation

/// What one rule decided for one entry.
public enum RuleVerdict: Sendable, Equatable {
    /// Write this status.
    case status(CoinageTxStatus)
    /// Write this status and record the block where execution was observed.
    case statusRecordingSuccess(CoinageTxStatus, BlockRef)
    /// Clear the recorded success block and write `pending`.
    case clearSuccessAndSetPending
    /// Nothing decided this entry from state; Rule 7 must search block bodies.
    case searchBodies
    /// A read failed. Abort this entry for this pass without writing anything.
    case abort
}

/// The rule table, evaluated in the spec's order — 0, 1, 2, 3, 4, 5, 6, 3b, 4b, 7 — first
/// match decides.
///
/// Pure over an ``EntrySnapshot``, so the whole table is directly unit-testable without a
/// chain or a store. Rule 7 needs an extra chain round-trip and so is returned as
/// ``RuleVerdict/searchBodies``; `RecoveryPass` performs the search and maps its outcome back
/// through ``verdict(forSearch:)``, which is likewise pure.
public struct RuleEvaluator: Sendable {
    public init() {}

    public func evaluate(_ snapshot: EntrySnapshot) -> RuleVerdict {
        if let verdict = ruleZero(snapshot) {
            return verdict
        }

        // Rule 1 — execution is visible at the finalized head.
        if snapshot.executed(atFinalized: true) {
            return .status(.finalizedSuccess)
        }

        // Rule 2 — execution is visible at the best head. Recording the block is what lets
        // Rule 0 decide the entry later without re-deriving that it executed.
        if snapshot.executed(atFinalized: false) {
            return .statusRecordingSuccess(.pendingSuccess, snapshot.view.best)
        }

        // Rules 3 and 4 read only the finalized head: they decide nothing before the window
        // closes, and past it whatever the extrinsic did happened below finality — so a
        // terminal verdict never rests on a block that can be reorged away.
        if snapshot.windowClosed {
            // Rule 3 — an output nothing could have removed is definitely not there.
            //
            // Ordered before Rule 5 as specified. The two are both absence-based and would
            // disagree on an entry whose output vanished, so this ordering is safe only
            // because handoff marks plus the Unique-consumer invariant guarantee a vanished
            // output is never `untouched`. A single missing handoff mark turns a successful
            // entry into a false FAILURE here.
            if snapshot.hasUntouchedAbsentOutput(atFinalized: true) {
                return .status(.failure)
            }

            // Rule 4 — an input is definitely still there to be spent.
            if snapshot.hasAvailableInput(atFinalized: true) {
                return .status(.failure)
            }
        }

        if snapshot.ownCoinInputs {
            // Rule 5 — every input is a proven-minted coin of ours and all are gone at
            // finality. Absence alone is ambiguous; `ownCoinInputs` is what resolves it.
            if snapshot.allInputsAbsent(atFinalized: true) {
                return .status(.finalizedSuccess)
            }

            // Rule 6 — the same, except one input survives at the finalized head, so the
            // consumption is only in the best chain.
            if snapshot.hasExistingInput(atFinalized: true),
               snapshot.allInputsAbsent(atFinalized: false) {
                return .status(.pendingSuccess)
            }
        }

        // Rules 3b and 4b short-circuit an entry with no positive evidence so it does not run
        // a body search on every new head. They stop at mortality because past it the search
        // is the only thing left that can decide the entry.
        //
        // For an entry already in PENDING_SUCCESS these demote rather than no-op, withdrawing
        // optimistic selectability from its outputs. That is intended: reaching here means
        // the success record was cleared and no positive evidence remains.
        if !snapshot.windowClosed {
            if snapshot.hasUntouchedAbsentOutput(atFinalized: false) {
                return .status(.pending)
            }

            if snapshot.hasAvailableInput(atFinalized: false) {
                return .status(.pending)
            }
        }

        return .searchBodies
    }

    /// Rule 7's verdict, given the outcome of the body search.
    ///
    /// Inclusion is not success: the events at the found block say which. The window ends at
    /// the finalized head, so both terminal verdicts rest on a finalized fact.
    public func verdict(forSearch outcome: BodySearchOutcome, windowClosed: Bool) -> RuleVerdict {
        switch outcome {
        case .foundSucceeded:
            .status(.finalizedSuccess)
        case .foundFailed:
            .status(.failure)
        case .foundOutcomeUnreadable:
            .status(.pending)
        case .notFoundWindowComplete where windowClosed:
            .status(.failure)
        case .notFoundWindowComplete,
             .incomplete:
            .status(.pending)
        }
    }
}

// MARK: - Rule 0

private extension RuleEvaluator {
    /// Rule 0 — recorded inclusion.
    ///
    /// Applies ahead of everything else whenever a success block is recorded. The field is
    /// only ever written where success is already proven, so this asks only whether that
    /// block is still real.
    ///
    /// Returns `nil` when no record exists, letting evaluation fall through to Rule 1.
    func ruleZero(_ snapshot: EntrySnapshot) -> RuleVerdict? {
        guard let detected = snapshot.entry.successDetectedAt else { return nil }

        switch snapshot.successBlockHash {
        case .failedRead:
            // No verdict, and the record is kept — it is still the best evidence we have.
            return .abort
        case let .present(hash) where hash == detected.hash:
            // Clause 2 / clause 3.
            return detected.number <= snapshot.view.finalized.number
                ? .status(.finalizedSuccess)
                : .status(.pendingSuccess)
        case .present,
             .absent:
            // Clause 1 — the recorded block was reorged out.
            //
            // Writing PENDING rather than only clearing the record is load-bearing: clearing
            // alone would leave the entry PENDING_SUCCESS with no evidence at all, keeping
            // its outputs spendable for a full mortality window on the strength of a block
            // that no longer exists.
            guard snapshot.executed(atFinalized: false) else {
                return .clearSuccessAndSetPending
            }
            return .statusRecordingSuccess(.pendingSuccess, snapshot.view.best)
        }
    }
}
