#!/usr/bin/env python3
"""Mutation sweep over the external payment (offramp) guards.

Same shape as `coinage_rule_mutation_sweep.py` / `top_up_mutation_sweep.py`: touch only the files that
decide an external payment's fate and run only the external payment tests. Each mutant removes or
weakens exactly one rule the contract states — origin-scoped identity, idempotent registration, the
verdict-vs-transient split, the bounded retry loop, cancellation safety, status semantics, the persisted
spend scope, and strategy-aware planning.

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
POLICY = f"{ROOT}/Service/ExternalPaymentRetryPolicy.swift"
CONTEXT = f"{ROOT}/Service/ExternalPaymentContext.swift"
RESCHEDULER = f"{ROOT}/Service/ExternalPaymentRescheduler.swift"
MODEL = f"{ROOT}/Model/ExternalPayment.swift"
FACTORY = f"{ROOT}/StateMachine/ExternalPaymentStateFactory.swift"
PLAN_STATE = f"{ROOT}/StateMachine/States/PlanPaymentState.swift"
OFFBOARD_STATE = f"{ROOT}/StateMachine/States/OffboardVouchersPaymentState.swift"
RETRY_STATE = f"{ROOT}/StateMachine/States/RetryPaymentState.swift"
PLANNER = f"{ROOT}/Planner/ExternalPaymentPlanner.swift"

DEFAULT_SIM = "F6327B69-0673-48AE-9515-C22A4B8CE8CE"  # iPhone 16
ONLY_TESTING = [
    "CoinageTests/ExternalPaymentModelTests",
    "CoinageTests/ExternalPaymentServiceTests",
    "CoinageTests/ExternalPaymentContextTests",
    "CoinageTests/ExternalPaymentReschedulerTests",
    "CoinageTests/ExternalPaymentStateTests",
    "CoinageTests/ExternalPaymentRestartTests",
    "CoinageTests/ExternalPaymentPlannerTests",
]

# (label, file, exact source to replace, replacement). Each removes or weakens one rule.
MUTANTS = [
    # --- identity & registration ---
    ("identity: the origin is dropped from the identifier", MODEL,
     '        "\\(origin):\\(paymentId)"',
     '        "\\(paymentId)"'),

    ("register: a known (origin, paymentId) is registered again", SERVICE,
     "        guard try await store.fetchPayment(byId: payment.id) == nil else {",
     "        guard true else {"),

    ("register: the requested spend scope is not persisted", SERVICE,
     "            spendScope: spendScope\n        )\n\n        try await registrar.register(payment)",
     "            spendScope: .spendable\n        )\n\n        try await registrar.register(payment)"),

    # --- verdict vs transient ---
    ("plan: a thrown error is a verdict", PLAN_STATE,
     "            return factory.makeRetryState(payment: payment, stage: .plan, error: error)",
     "            return factory.makeFailedState(payment: payment, reason: error.localizedDescription)"),

    ("plan: insufficient balance is retried instead of failed", PLAN_STATE,
     "                return factory.makeFailedOrPartial(payment: payment, reason: \"Insufficient balance\")",
     "                return factory.makeRescheduledState(payment: payment, until: Date())"),

    ("retry: the failing stage is not the one persisted", RETRY_STATE,
     "        currentPayment.stage = stage",
     "        currentPayment.stage = .plan"),

    ("offboard: a stale plan fails instead of re-planning", OFFBOARD_STATE,
     "                guard !vouchers.isEmpty, try await allSpendable(vouchers, factory: factory) else {\n"
     "                    return factory.makePlanState(payment: payment)",
     "                guard !vouchers.isEmpty, try await allSpendable(vouchers, factory: factory) else {\n"
     "                    return factory.makeFailedState(payment: payment, reason: \"stale\")"),

    ("memo: offboarding is restored as plan (rejoin dropped)", FACTORY,
     "            makeOffboardVouchersState(payment: payment, vouchers: [])",
     "            makePlanState(payment: payment)"),

    # --- the bounded retry loop ---
    ("loop: the retry window is never checked", SERVICE,
     "            if retryPolicy.hasWindowElapsed(since: payment.createdAt) {",
     "            if false {"),

    ("loop: cancellation persists failed", SERVICE,
     "            guard !Task.isCancelled else { return }",
     "            if Task.isCancelled {\n                await persistRetryWindowElapsed(payment)\n                return\n            }"),

    ("backoff: every retry is immediate", POLICY,
     "        min(TimeInterval(attempt) * backoff, maxBackoff)",
     "        0"),

    ("observe: rows with a future readyAt are processed", SERVICE,
     "                        .filter { $0.readyAt <= Date() }",
     "                        .filter { _ in true }"),

    ("context: a scheduled payment is started a second time", CONTEXT,
     "        guard paymentId != currentPaymentId,\n"
     "              !pendingTasks.contains(where: { $0.paymentId == paymentId })\n        else {",
     "        guard true else {"),

    ("rescheduler: the wakeup leaves the stage rescheduled", RESCHEDULER,
     "            updated.stage = .plan",
     "            updated.stage = .rescheduled"),

    # --- what the product is told ---
    ("status: an unknown id is silently dropped", SERVICE,
     "            .map { payment -> ExternalPaymentStatus in\n"
     "                guard let payment else { return .failed(reason: \"unknown payment\") }",
     "            .compactMap { payment -> ExternalPaymentStatus? in\n"
     "                guard let payment else { return nil }"),

    ("status: partially completed is reported as failed", SERVICE,
     "        case .completed,\n             .partiallyCompleted:\n            .completed",
     "        case .completed:\n            .completed\n        case .partiallyCompleted:\n"
     "            .failed(reason: failureReason ?? \"Unknown\")"),

    ("status: the stream never ends after a terminal status", SERVICE,
     "                        if status.isTerminal { break }",
     "                        _ = status.isTerminal"),

    # --- partial unloads: settle and retry the remainder ---
    ("partial: a partial unload is terminal instead of re-planned", OFFBOARD_STATE,
     "        return factory.makePlanState(payment: next)",
     "        return factory.makePartiallyCompletedState(payment: next, reason: \"partial\")"),

    ("partial: the next round reuses the settled group", OFFBOARD_STATE,
     "        next.round += 1",
     "        next.round += 0"),

    ("partial: the remainder is planned as the full amount", PLAN_STATE,
     "                amount: payment.remainingInPlanks,",
     "                amount: payment.amountInPlanks,"),

    ("partial: nothing delivered after a settled round is called failed", FACTORY,
     "        payment.settledInPlanks > 0",
     "        false"),

    # --- strategy-aware planning & the persisted scope ---
    ("planner: no verdicts yet is treated as no funds", PLANNER,
     "            return .needsReschedule(\n                after: Date(timeIntervalSinceNow: rescheduleDelay),\n"
     "                selection(vouchers: [], coins: [], amount: amount, scope: scope)\n            )\n        }\n\n"
     "        let spendableVoucherTotal",
     "            return .notEnoughBalance\n        }\n\n        let spendableVoucherTotal"),

    ("planner: gaining-privacy vouchers are spent as if spendable", PLANNER,
     "        let spendableVoucherTotal = totalValue(of: assets.spendableVouchers, context: context)",
     "        let spendableVoucherTotal = totalValue(\n"
     "            of: assets.spendableVouchers + assets.gainingPrivacyVouchers,\n            context: context\n        )"),

    ("planner: the record's scope is ignored when planning", PLAN_STATE,
     "                scope: payment.spendScope",
     "                scope: .spendable"),

    ("offboard: re-validation ignores the record's scope", OFFBOARD_STATE,
     "        guard let assets = try await factory.spendableAssets.spendableAssets(scope: payment.spendScope) else {",
     "        guard let assets = try await factory.spendableAssets.spendableAssets(scope: .spendable) else {"),

    ("preview: the second pass never widens", SERVICE,
     "        guard !spendable.isExecutable else { return spendable }",
     "        return spendable"),
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
