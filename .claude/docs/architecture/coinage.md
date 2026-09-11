# Coinage Architecture

## Overview

Coinage is the payment primitive for the Polkadot app — managing digital coins with derivation indices, values, and lifecycle states. Used for in-app payments, game rewards, and peer transfers.

## Key Components

### Package
- **Coinage** (`Packages/Coinage/`) — core coinage logic, coin models, transfer planning

### Module
- **Coinage** (`Modules/Coinage/`) — UI for coinage operations

### Services (in ServiceCoordinator)
- `coinageService` — coinage state management
- `coinageBackupSyncService` — iCloud backup synchronization

## Coin Model

A coin (`Packages/Coinage/Sources/Models/Coin.swift`) has:
- `exponent` — coin value as a power of two (`2^n`)
- `derivationIndex` — unique derivation path
- `age` — on-chain age; `nil` = never seen on chain, `0` = fresh from unload/split
- `isOnchain` — on-chain presence, written only by chain sync (`age != nil ∧ ¬isOnchain` = seen then vanished)
- `handoffMark` — whether the coin has been handed off to a peer, and how far along
- `publicKey` — on-chain account id derived from `derivationIndex`, cached so the durability layer never re-derives it

## Key Rules

1. **Use the `KeyDerivation` package** — never hand-roll coin keypair derivation. The derivation domain must be coinage-specific (never reused across features).
2. **Zero balance handling** — properly handle zero-balance edge cases
3. **Deterministic fund amounts** — top-up affordances (the "+" fund button) must compute the resulting coin set from a deterministic plan: same input balance + same target → same coin denominations every time. Don't sample randomly, don't depend on iteration order over an unsorted set, and don't let the displayed preview drift from the amount actually submitted. The fix was switching from "pick coins as we go" to producing a stable plan up-front, then rendering and submitting from that plan.
4. **Exact-match edge in transfer planning** — when the requested amount exactly equals one of the candidate coin denominations, the planner must take the single-coin path and skip the split/unload branches. Hitting split logic with an exact match crashes because it tries to break a coin it doesn't need to. The same care applies to the "no split needed" boundary in `Coinage` transfer planning: always test the exact equality case alongside under/over.

## Balance (strategy-aware, two-pass)

`CoinageBalanceService` emits a single `CoinageBalance` with three plank buckets:

- `availablePrivate` — spendable now at no privacy cost (coins the strategy leaves usable + usable vouchers).
- `gainingPrivacy` — `{ amount, canSpendWithConfirmation }`; deliberately held back, some strategies release it behind a confirmation (`maxPrivacy` does not).
- `pending` — arriving, or past the chain's age ceiling; never spendable.

Derived: `available` = `availablePrivate (+ gainingPrivacy.amount when canSpendWithConfirmation)`; `total` = all three. Amounts are planks — render via `CoinageBalanceServiceProtocol.denominationContext` (`decimal(fromPlanks:)`).

**Consumer semantics** (mirrors Android): spend-sufficiency and the primary "spendable" figure use `availablePrivate`; the reachable-with-confirmation figure uses `available`. Products sufficiency → `availablePrivate`; TransferAmount `secured`/`lowPrivacy` → `availablePrivate`/`gainingPrivacy.amount` (the latter zeroed when `!canSpendWithConfirmation`); AssetDetails total → `total`, locked → `total − available`.

**`BalanceEvaluationMode` (immediate | complete).** The balance renders nothing until the first verdicts land, so `CoinRecyclingEvaluator` runs a two-pass: when it has no verdicts yet it first publishes an `immediate` pass (no chain read — `RingCapacityProviding.peekCapacities` returns only memoised capacities, and `RecyclingStrategyProviding.coinStrategy(for:mode:)` skips the quota read, treating quota as exhausted so only the chain age-ceiling gates), then a `complete` pass consults every limit and corrects. The correction is downward-only — a coin the policy would hold shows spendable until `complete` moves it, never the reverse. Recycling is triggered only off the `complete` pass. The balance service itself uses `immediate` (peek) capacities so it never blocks.

## Transfer Planning

Transfer plans determine how coins are spent:
- Exact coins — use specific coins
- Split — divide coins for partial amounts
- Unload and split — complex multi-step transfers

## Payment Processing

- `CoinagePaymentProcessingExtension` watches on-chain events for payment confirmations
- Integrates with chat for payment request/confirmation messages
- See `architecture/chat-extension.md` for chat integration

## External Payments (offramp)

`Packages/Coinage/Sources/ExternalPayment/` moves CASH out of the wallet on behalf of a product
(`getcash` withdraw) or the in-app pay deeplink. Persisted as `ExternalPayment` rows
(`CDExternalPayment`, `ExternalPaymentMapper`, CoreData v47 adds `settledInPlanks`) and driven by a
persist-per-transition state machine: `Plan → OffboardVouchers` when spendable vouchers cover the
amount, `Plan → OnboardCoins → OffboardVouchers` when coins must be recycled first, ending in
`Completed / PartiallyCompleted / Failed`.

- **Identity** is `(origin, paymentId)`; the record id is `"<origin>:<paymentId>"`
  (`ExternalPayment.identifier(origin:paymentId:)`), so the same product-supplied id under two origins
  is two payments and the durability group ids stay unique. Registration (`initiatePayment`) validates
  uniqueness through a serialized registrar and throws `ExternalPaymentError.alreadyExists`.
- **Consent happens before registration, not in the worker.** The caller (host API or the in-app
  flow) shows the gaining-privacy sheet whenever the recycling strategy is not `minPrivacy`
  (`PaymentPrivacyGate`). Because the user has consented, the worker may spend anything spendable
  on-chain: the planner is **structural** (`TrackedVoucher.isSelectable`, `TrackedCoin.isSelectable`)
  and reads no strategy buckets, verdicts or `readyAt`. There is no persisted spend scope.
- **Planning** (`ExternalPaymentPlanner.plan(amount:context:mustInclude:)`): `mustInclude` vouchers
  first, then spendable vouchers largest-first → `.ready(Selection)`; else the deficit from spendable
  coins → `.loadCoins(Selection)` (the selection carries the exact vouchers the coins top up); else
  `.notEnoughBalance`.
- **Onboarding** recycles the chosen coins under the payment's own group
  (`external-payment:<id>:recycle`) and awaits `CoinageRecyclingServicing.observeRecycling(groupId:)`:
  `pending` keeps waiting, `allRecycled(vouchers:finalized:)` (best-block inclusion is enough) checks
  that `exactVouchers + recycled` cover the amount and moves to offboarding, `incomplete` or a
  shortfall fails the payment. `recycleCoins(_:groupId:)` re-joins a group that already has entries,
  so a relaunch never recycles twice; the re-entered state (exact selection unknown) re-plans with
  the recycled vouchers as `mustInclude`.
- **Offboarding** submits the plan straight to `OffboardVouchersForPaymentService` under
  `external-payment:<id>` (re-joining an existing group on relaunch) and awaits one verdict:
  `.success` completes with `settledInPlanks = amount`; `.partialSuccess` persists the delivered
  value as `partiallyCompleted` and is terminal; `.failed`, a submission error and any thrown error
  persist `failed`. There are no retries, rounds or reschedules.
- **Cancellation is the one non-verdict.** `CancellationError` (the observation task is cancelled by
  `throttle()`) persists the stage unchanged via `InterruptedPaymentState`; the next `setup` re-runs the
  row. Every other thrown error fails the payment in that run.
- **Status semantics** (`subscribePaymentStatus(origin:paymentId:)`): unknown id →
  `.failed("unknown payment")` once, then end; `partiallyCompleted` → `.partiallyCompleted(settledInPlanks:)`
  (the host reports `PartiallyClaimed` with the value); legacy `rescheduled` rows report `.processing`
  and resume as `plan`; duplicates collapse; the stream ends after the first terminal status.
- Tests: `Packages/Coinage/Tests/ExternalPayment/` (real service + state machine over an in-memory
  store, a scripted recycler and a group-aware durability double) and
  `Tests/Recycling/RecyclingStatusFoldingTests.swift`; mutation sweep
  `Packages/Coinage/Tools/external_payment_mutation_sweep.py`.

## Seams

| Seam                    | Where                          | When to touch                    |
|-------------------------|--------------------------------|----------------------------------|
| Coin models             | `Packages/Coinage/`           | Coin structure changes           |
| Transfer planning       | `Packages/Coinage/`           | New transfer strategies          |
| External payments       | `Packages/Coinage/Sources/ExternalPayment/` | Offramp identity, retry, status, planner scope |
| Coinage UI              | `Modules/Coinage/`            | Coinage screen changes           |
| Backup sync             | ServiceCoordinator             | Backup/restore flow changes      |
| Instance ID config      | `AppConfig.Coinage.instanceId` | Remote config schema or app instance strategy changes |
