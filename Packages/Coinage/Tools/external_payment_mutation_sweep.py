#!/usr/bin/env python3
"""Mutation sweep over the external payment (offramp) guards.

Same shape as `coinage_rule_mutation_sweep.py` / `top_up_mutation_sweep.py`: touch only the files that
decide an external payment's fate and run only the external payment tests. Each mutant removes or
weakens exactly one rule the contract states — origin-scoped identity, idempotent registration, every
error is a verdict except cancellation, recycling awaited and checked for sufficiency, one durability
group per payment, partial unloads terminal with the settled value, status semantics, and structural
planning with forced vouchers.

Read a SURVIVED line as "no test distinguishes this rule's presence from its absence".

Usage, from the repository root:
    python3 Packages/Coinage/Tools/external_payment_mutation_sweep.py
    python3 Packages/Coinage/Tools/external_payment_mutation_sweep.py --list
    python3 Packages/Coinage/Tools/external_payment_mutation_sweep.py --sim <simulator-udid>

Sources are restored on every exit path — normal exit, Ctrl-C, SIGTERM — and the restore is verified before
the script returns.
"""
import argparse
import os
import signal
import subprocess
import sys

ROOT = "Packages/Coinage/Sources/ExternalPayment"
SERVICE = f"{ROOT}/Service/ExternalPaymentService.swift"
CONTEXT = f"{ROOT}/Service/ExternalPaymentContext.swift"
MODEL = f"{ROOT}/Model/ExternalPayment.swift"
FACTORY = f"{ROOT}/StateMachine/ExternalPaymentStateFactory.swift"
PLAN_STATE = f"{ROOT}/StateMachine/States/PlanPaymentState.swift"
ONBOARD_STATE = f"{ROOT}/StateMachine/States/OnboardCoinsPaymentState.swift"
OFFBOARD_STATE = f"{ROOT}/StateMachine/States/OffboardVouchersPaymentState.swift"
PLANNER = f"{ROOT}/Planner/ExternalPaymentPlanner.swift"
RECYCLER = "Packages/Coinage/Sources/Recycling/CoinageRecyclingService.swift"

DEFAULT_SIM = "F6327B69-0673-48AE-9515-C22A4B8CE8CE"  # iPhone 16
ONLY_TESTING = [
    "CoinageTests/ExternalPaymentModelTests",
    "CoinageTests/ExternalPaymentServiceTests",
    "CoinageTests/ExternalPaymentContextTests",
    "CoinageTests/ExternalPaymentStateTests",
    "CoinageTests/ExternalPaymentRestartTests",
    "CoinageTests/ExternalPaymentPlannerTests",
    "CoinageTests/RecyclingStatusFoldingTests",
    "CoinageTests/CoinageRecyclingServiceTests",
]

# (label, file, exact source to replace, replacement). Each removes or weakens one rule.
MUTANTS = [
    ("identity: the origin is dropped from the identifier", MODEL,
     '        "\\(origin):\\(paymentId)"',
     '        paymentId'),
    ("register: a known (origin, paymentId) is registered again", SERVICE,
     "        guard try await store.fetchPayment(byId: payment.id) == nil else {\n"
     "            throw ExternalPaymentError.alreadyExists\n"
     "        }\n",
     ""),
    ("plan: a thrown error keeps the stage instead of failing", PLAN_STATE,
     "            return factory.makeFailedState(payment: payment, stage: .plan, error: error)",
     "            return factory.makeInterruptedState(payment: payment, stage: .plan)"),
    ("plan: insufficient balance is not a verdict", PLAN_STATE,
     '                return factory.makeFailedState(payment: payment, reason: "Insufficient balance")',
     '                return factory.makeInterruptedState(payment: payment, stage: .plan)'),
    ("cancel: cancellation persists failed", FACTORY,
     "        error is CancellationError",
     "        false"),
    ("onboard: recycling continues on incomplete", ONBOARD_STATE,
     '                case .incomplete:\n'
     '                    return factory.makeFailedState(payment: payment, reason: "recycling incomplete")',
     '                case .incomplete:\n'
     '                    continue'),
    ("onboard: pending is treated as recycled (never awaits)", ONBOARD_STATE,
     "                case .pending:\n                    continue",
     "                case .pending:\n                    return try await continueWithRecycled([], factory: factory)"),
    ("onboard: the sufficiency check is dropped", ONBOARD_STATE,
     "        guard covered >= payment.amountInPlanks else {",
     "        guard covered >= 0 else {"),
    ("onboard: re-entry offboards the recycled vouchers alone instead of re-planning", ONBOARD_STATE,
     "        guard !exactVouchers.isEmpty else {\n"
     "            return try await replan(including: recycled, factory: factory)\n"
     "        }\n",
     ""),
    ("recycler: a re-joined group is submitted again", RECYCLER,
     "        if let groupId, try await !txService.getOperationGroupStatuses(groupId).isEmpty {\n"
     '            logger.debug("Recycling group \\(groupId) already registered, re-joining")\n'
     "            return 0\n"
     "        }\n",
     ""),
    ("fold: a failed entry still counts as recycled", RECYCLER,
     "        guard !entries.contains(where: { $0.status == .failure }) else {\n"
     "            return .incomplete\n"
     "        }\n",
     ""),
    ("fold: a live entry is reported as recycled", RECYCLER,
     "        guard !entries.isEmpty, entries.allSatisfy(\\.status.isArrived) else {",
     "        guard !entries.isEmpty else {"),
    ("offboard: a partial unload is reported as completed", OFFBOARD_STATE,
     '                return factory.makePartiallyCompletedState(\n'
     '                    payment: settled,\n'
     '                    reason: "\\(executed) of \\(total) unload transactions executed"\n'
     '                )',
     '                _ = (executed, total)\n'
     '                return factory.makeCompletedState(payment: settled)'),
    ("offboard: the settled value is not persisted", OFFBOARD_STATE,
     "                settled.settledInPlanks = settledInPlanks",
     "                settled.settledInPlanks = 0"),
    ("offboard: a failed unload keeps the stage", OFFBOARD_STATE,
     '                return factory.makeFailedState(payment: payment, reason: "no unload transaction executed")',
     '                return factory.makeInterruptedState(payment: payment, stage: .offboardVouchers)'),
    ("status: an unknown id is silently dropped", SERVICE,
     '                guard let payment else { return .failed(reason: "unknown payment") }',
     '                guard let payment else { return .processing }'),
    ("status: partially completed hides the settled amount", SERVICE,
     "            .partiallyCompleted(settledInPlanks: settledInPlanks)",
     "            .partiallyCompleted(settledInPlanks: 0)"),
    ("status: the stream never ends after a terminal status", SERVICE,
     "            .removeDuplicates()\n            .endAfterTerminal()",
     "            .removeDuplicates()\n            .eraseToAnyAsyncSequence()"),
    ("memo: a legacy rescheduled row is restored as failed", FACTORY,
     "        case .plan,\n             .rescheduled:\n            makePlanState(payment: payment)",
     "        case .plan:\n            makePlanState(payment: payment)\n"
     "        case .rescheduled:\n            makeFailedState(payment: payment, reason: \"legacy\")"),
    ("context: a queued payment is started a second time", CONTEXT,
     "              !pendingTasks.contains(where: { $0.paymentId == paymentId })",
     "              true"),
    ("planner: non-selectable vouchers are spent", PLANNER,
     "            .filter { $0.isSelectable && !forced.contains($0.voucher.derivationIndex) }",
     "            .filter { !forced.contains($0.voucher.derivationIndex) }"),
    ("planner: non-selectable coins are recycled", PLANNER,
     "            .filter(\\.isSelectable)\n            .map(\\.coin)",
     "            .map(\\.coin)"),
    ("planner: mustInclude is not forced into the selection", PLANNER,
     "            let selected = mustInclude + select(from: spendableVouchers, target: amount, context: context) {\n"
     "                totalValue(of: mustInclude, context: context)\n"
     "            }",
     "            let selected = select(from: spendableVouchers, target: amount, context: context) { 0 }"),
]

def run_suite(sim):
    only = []
    for target in ONLY_TESTING:
        only += ["-only-testing:" + target]

    result = subprocess.run(
        ["xcodebuild", "test",
         "-project", "polkadot-app.xcodeproj",
         "-scheme", "polkadot-app",
         "-destination", f"platform=iOS Simulator,id={sim}"] + only,
        capture_output=True, text=True,
    )
    out = result.stdout + result.stderr
    if "** TEST SUCCEEDED **" in out:
        return ("survived", None)
    if "** TEST FAILED **" in out:
        return ("killed", "test")
    if "** BUILD FAILED **" in out:
        return ("killed", "compile")
    return ("killed", f"other(exit={result.returncode})")


def main():
    parser = argparse.ArgumentParser(description="Mutation sweep over the external payment guards")
    parser.add_argument("--list", action="store_true", help="print the mutants and exit without running")
    parser.add_argument("--sim", default=DEFAULT_SIM, help="simulator UDID to run the tests on")
    parser.add_argument("--from", dest="start", type=int, default=1,
                        help="1-based index of the first mutant to run (resume an interrupted sweep)")
    args = parser.parse_args()

    if not os.path.isfile("polkadot-app.xcodeproj/project.pbxproj") or not os.path.isfile(SERVICE):
        sys.exit("run this from the repository root")

    if args.list:
        for index, (label, _, _, _) in enumerate(MUTANTS, start=1):
            print(f"  {index:2d}. {label}")
        return

    originals = {path: open(path).read() for _, path, _, _ in MUTANTS}
    survived, killed, skipped = [], [], []

    # Turn a kill signal into an exception so the restore in `finally` still runs. Without this a sweep
    # stopped by a supervisor leaves a mutant sitting in the source, and whatever runs next measures it.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit("terminated"))

    try:
        for index, (label, path, old, new) in enumerate(MUTANTS, start=1):
            if index < args.start:
                continue
            original = originals[path]
            if original.count(old) != 1:
                skipped.append(label)
                print(f"SKIP     {label}  (pattern matched {original.count(old)}x — source moved under it)", flush=True)
                continue

            open(path, "w").write(original.replace(old, new, 1))
            verdict, reason = run_suite(args.sim)
            open(path, "w").write(original)  # restore before the next mutant builds

            if verdict == "killed":
                killed.append(label)
                print(f"killed   {label}  ({reason})", flush=True)
            else:
                survived.append(label)
                print(f"SURVIVED {label}", flush=True)
    finally:
        for path, text in originals.items():
            open(path, "w").write(text)
            assert open(path).read() == text, f"failed to restore {path}"

    if skipped:
        # Not a note: a pattern that no longer matches means the rule it names is gone or was rewritten,
        # and the sweep silently stopped testing it.
        print(f"\n{len(skipped)} mutant(s) could not be applied — the sweep is out of date with the source:")
        for label in skipped:
            print(f"  {label}")

    print(f"\nkilled {len(killed)}/{len(killed) + len(survived)} applied mutants")
    if survived:
        print("survivors:")
        for label in survived:
            print(f"  {label}")

    sys.exit(1 if survived or skipped else 0)


if __name__ == "__main__":
    main()
