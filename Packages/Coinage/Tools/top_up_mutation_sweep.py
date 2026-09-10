#!/usr/bin/env python3
"""Mutation sweep over the RFC-0006 top-up guards (iOS port).

Adapted from `feature/products/impl/tools/top_up_mutation_sweep.py` in the Android repo. Same spirit:
touch only the files that decide a top-up's fate and run only the top-up tests. Each mutant removes or
weakens exactly one rule the host call's contract states — idempotency, one-claim-per-source, terminality,
verdict immutability, group namespacing, and the translation from what coinage detected into what a product
is told.

Read a SURVIVED line as "no test distinguishes this rule's presence from its absence".

iOS split note: on Android the coinage→product status translation lives in `ExecuteTopUpUseCase`, in scope
for these tests. On iOS the amount/shortfall arithmetic lives one layer down, in the claim services
(`ClaimCoinsService`/`ClaimAssetService`), which the top-up tests stub. Those mutants therefore belong to a
coinage-claim sweep, not this one, and are intentionally absent here.

Usage, from the repository root:
    python3 Packages/Coinage/tools/top_up_mutation_sweep.py
    python3 Packages/Coinage/tools/top_up_mutation_sweep.py --list
    python3 Packages/Coinage/tools/top_up_mutation_sweep.py --sim <simulator-udid>

Sources are restored on every exit path — normal exit, Ctrl-C, SIGTERM — and the restore is verified before
the script returns.
"""
import argparse
import os
import signal
import subprocess
import sys

COINAGE = "Packages/Coinage/Sources/IncomingPayment"
SERVICE = f"{COINAGE}/IncomingPaymentService.swift"
DESCRIPTOR = f"{COINAGE}/Model/IncomingPaymentSourceDescriptor.swift"
STATUS = f"{COINAGE}/Model/IncomingPaymentStatus.swift"
DETECT = f"{COINAGE}/Model/IncomingPaymentStatus+Detection.swift"
MODEL = f"{COINAGE}/Model/IncomingPayment.swift"
CONTEXT = f"{COINAGE}/IncomingPaymentContext.swift"

DEFAULT_SIM = "F6327B69-0673-48AE-9515-C22A4B8CE8CE"  # iPhone 16
ONLY_TESTING = [
    "CoinageTests/IncomingPaymentModelTests",
    "CoinageTests/IncomingPaymentSourceDescriptorTests",
    "CoinageTests/IncomingPaymentContextTests",
    "CoinageTests/IncomingPaymentServiceTests",
    "CoinageTests/IncomingPaymentSweepTests",
    "ProductsTests/PaymentTopUpRequestDtoTests",
]

# (label, file, exact source to replace, replacement). Each removes or weakens one rule.
MUTANTS = [
    # --- idempotency: an id names one operation, for good ---
    ("accept: a used id is handed out again", SERVICE,
     "        if try await store.fetch(groupId: groupId) != nil {",
     "        if false {"),

    # --- one live claim per source ---
    ("accept: a busy source is accepted", SERVICE,
     "            if descriptor.drawsOnSameFunds(as: otherDescriptor, sameProduct: other.productId == productId) {",
     "            if false {"),

    ("busy: one product's account index blocks another's", DESCRIPTOR,
     "            sameProduct && lhs == rhs",
     "            lhs == rhs"),

    ("busy: overlapping coins are not the same source", DESCRIPTOR,
     "            !Set(lhs).isDisjoint(with: Set(rhs))",
     "            lhs == rhs"),

    # --- terminality & verdict immutability ---
    ("settle: a non-terminal status yields a verdict", STATUS,
     "        case .detecting,\n             .claiming:\n            nil",
     "        case .detecting,\n             .claiming:\n            .notClaimed"),

    ("settle: the source outlives the verdict", SERVICE,
     "        secretStore.remove(groupId: payment.groupId)",
     "        _ = payment.groupId"),

    ("subscribe: a recorded verdict is re-derived", SERVICE,
     "            return payment.outcome.map(IncomingPaymentStatus.init(outcome:)) ?? .detecting",
     "            return IncomingPaymentStatus.detecting"),

    ("subscribe: an unknown id is not reported as notFound", SERVICE,
     "                throw IncomingPaymentError.notFound(paymentId)",
     "                return .notClaimed"),

    ("isTerminal: an unfinalized claim is terminal", STATUS,
     "        case let .claimed(finalized):\n            finalized\n        case .claimedPartially,\n"
     "             .notClaimed:\n            true",
     "        case let .claimed(finalized):\n            true\n        case .claimedPartially,\n"
     "             .notClaimed:\n            true"),

    ("isTerminal: nothing is terminal", STATUS,
     "        case .claimedPartially,\n             .notClaimed:\n            true",
     "        case .claimedPartially,\n             .notClaimed:\n            false"),

    # --- scheduling: one runner per operation ---
    ("context: a running top-up is started a second time", CONTEXT,
     "        guard tasks[groupId] == nil, !pending.contains(where: { $0.groupId == groupId }) else {",
     "        guard true else {"),

    # --- the group a top-up's transactions land in ---
    ("group: two products share one top-up group", MODEL,
     '        "top up:\\(productId):\\(paymentId)"',
     '        "top up:\\(paymentId)"'),

    ("group: the \"top up:\" namespace is dropped", MODEL,
     '        "top up:\\(productId):\\(paymentId)"',
     '        "\\(productId):\\(paymentId)"'),

    # --- what the product is told ---
    ("status: a retry in progress is called partial", DETECT,
     "        case .claiming,\n             .claimingRest:\n            self = .claiming",
     "        case .claiming:\n            self = .claiming\n        case let .claimingRest(claimed):\n"
     "            self = .claimedPartially(actualClaimed: claimed)"),

    # --- the retry window belongs to the operation ---
    ("window: the retry window is not the one the operation opened with", SERVICE,
     "addingTimeInterval(CoinageConstants.topUpRetryWindow)",
     "addingTimeInterval(CoinageConstants.topUpRetryWindow * 2)"),
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
    parser = argparse.ArgumentParser(description="Mutation sweep over the top-up guards")
    parser.add_argument("--list", action="store_true", help="print the mutants and exit without running")
    parser.add_argument("--sim", default=DEFAULT_SIM, help="simulator UDID to run the tests on")
    args = parser.parse_args()

    if not os.path.isfile("polkadot-app.xcodeproj/project.pbxproj") or not os.path.isfile(SERVICE):
        sys.exit("run this from the repository root")

    if args.list:
        for label, _, _, _ in MUTANTS:
            print(f"  {label}")
        return

    originals = {path: open(path).read() for _, path, _, _ in MUTANTS}
    survived, killed, skipped = [], [], []

    # Turn a kill signal into an exception so the restore in `finally` still runs. Without this a sweep
    # stopped by a supervisor leaves a mutant sitting in the source, and whatever runs next measures it.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit("terminated"))

    try:
        for label, path, old, new in MUTANTS:
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
