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
(`CDExternalPayment`, `ExternalPaymentMapper`) and driven by a persist-per-transition state machine
(`Plan → OnboardCoins → Plan → OffboardVouchers → Completed/PartiallyCompleted/Failed`, or
`Rescheduled` with a `readyAt` wakeup).

- **Identity** is `(origin, paymentId)`; the record id is `"<origin>:<paymentId>"`
  (`ExternalPayment.identifier(origin:paymentId:)`), so the same product-supplied id under two origins
  is two payments and the durability group id `external-payment:<id>` stays unique. Registration
  (`initiatePayment`) validates uniqueness and throws `ExternalPaymentError.alreadyExists`; there is
  no separate pre-check.
- **Spend scope is persisted** (`spendScope`, CoreData v46). Both callers widen the same way transfers
  do: spendable funds first, gaining-privacy funds only when the strategy allows confirmed spends and
  only after the user confirms. The in-app flow previews two-pass like `previewTransfer`; a product
  payment resolves the scope from one balance snapshot (`PaymentSpendScopeResolver`) and shows the
  same gaining-privacy sheet through `PaymentPrivacyConfirming` (never allowlisted). The record carries
  the consent, so a restart plans with it.
- **Partial unloads settle and retry** (`settledInPlanks`, `round`, CoreData v46). When some unload
  groups finalize and others fail, `OffboardVouchersPaymentState` books the delivered value (finalized
  entries' voucher inputs minus their surplus outputs), advances `round`, and re-plans
  `remainingInPlanks` under a fresh durability group (`external-payment:<id>:r<round>`; round 0 keeps
  the legacy id so in-flight rows re-join after an upgrade). A verdict after something settled is
  `partiallyCompleted`, never `failed`.
- **Planner reads strategy buckets**, never raw structural readiness: `SpendableAssetsProviding`
  (`RecyclingAwareSpendableAssetsProvider` over `CoinageAssetSelector` + evaluator verdicts + voucher
  usability). No verdicts yet → reschedule. Gaining-privacy funds outside the scope reschedule at the
  earliest `readyAt`; they are never spent or recycled early by a payment.
- **Verdict vs transient**: planner `notEnoughBalance` and an unload outcome of `.failed` persist
  `failed` immediately. A thrown error (RPC, planner, cancellation) yields `RetryPaymentState`, which
  persists the failing stage unchanged with the error as `failureReason`; `ExternalPaymentService`
  detects "machine returned but stage is non-terminal" and re-runs under `ExternalPaymentRetryPolicy`
  (30 s × attempt, capped at 5 min, within 1 h of `createdAt`; then `failed` with the last error).
  Cancellation never persists `failed`. Retries re-enter offboarding through the durability group
  re-join exactly like crash re-entry, so a group is registered once.
- **Status semantics** (`subscribePaymentStatus`): unknown id → `.failed("unknown payment")` once,
  then end; `partiallyCompleted` → `.completed` (money moved; the host status has no partial variant); `rescheduled` → `.processing`; duplicates collapse;
  the stream ends after the first terminal status.
- Tests: `Packages/Coinage/Tests/ExternalPayment/` (real service + state machine over an in-memory
  store and a group-aware durability double); mutation sweep
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
