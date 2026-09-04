---
title: Coin recycling strategies — iOS logic layer (stage 1)
status: planned
created: 2026-09-03
source: ../Coinage/privacy/PLAN.md + HANDOFF-coin-recycling.md (Android decisions D1–D20); ../polkadot-android-community final code
scope_decisions:
  - Stage 1 logic only — no privacy-switch UI, no strategy chooser, no confirmation sheet (stage 2)
  - Foreground-only recycling — delete the BGProcessingTask scheduler; the evaluator verdict is the single trigger
  - Final D20 three-bucket balance — spendable / gainingPrivacy(amount, canSpendWithConfirmation) / pending
packages_touched:
  - Packages/Coinage
  - polkadot-app (Common/Coinage, CoreData model, app test target)
files_touched:
  # New — Packages/Coinage/Sources/Recycling/Strategy/
  - Recycling/Strategy/CoinRecyclingStrategyProtocol.swift: new seam — batch coin gating + voucher usability + allowsConfirmedSpend
  - Recycling/Strategy/RecyclingParams.swift: new — BigRational budget + min age + ring-fill + allowsConfirmedSpend
  - Recycling/Strategy/RecyclingStrategyType.swift: new enum .minPrivacy | .balanced | .maxPrivacy + params(forcedRecyclingAge:)
  - Recycling/Strategy/CoinRecyclingState.swift: new enum .mustRecycle | .toRecycle | .allowUse
  - Recycling/Strategy/RecyclingSnapshot.swift: new — total + unavailable (Balance)
  - Recycling/Strategy/VoucherUsabilityContext.swift: new — ringCapacities keyed by exponent + capacity(for:)
  - Recycling/Strategy/RecyclingVerdicts.swift: new typealias [DerivationIndex: CoinRecyclingState]
  - Recycling/Strategy/ParametricRecyclingStrategy.swift: new — the single policy
  - Recycling/Strategy/EnsureChainLimitsStrategy.swift: new decorator — forces .mustRecycle at the chain ceiling
  - Recycling/Strategy/EnsureQuotaLimitsStrategy.swift: new decorator — empty verdicts when quota low
  - Recycling/Strategy/RecyclingStrategyProvider.swift: new — resolves presets + wraps decorators
  - Recycling/Strategy/CoinagePreClassification.swift: new — preClassifyCoins/preClassifyVouchers + CoinBuckets/VoucherBuckets
  - Recycling/CoinRecyclingEvaluator.swift: new actor — throttled verdict subject + recycle trigger
  - Recycling/RingCapacityProvider.swift: new actor — memoised 2^exp − 257 per denomination
  - Transfer/UnloadToken/UnloadQuotaTracker.swift: new — remaining-quota reader + cache + noteUnloadHappened
  - Recycling/Settings/CoinageRecyclingStrategySettings.swift: new protocol (package api)
  # Modified — Packages/Coinage
  - Recycling/CoinageRecyclingService.swift: strip decision/scheduling; keep submission + idle guard behind recycle(_:)
  - Recycling/CoinageRecyclingServicing.swift: narrow protocol to recycle(_:)
  - Services/CoinageBalance.swift: reshape to three buckets (spendable/gainingPrivacy/pending)
  - Services/CoinageBalanceService.swift: onto pre-classifiers + evaluator verdicts; keep own tick; withhold first emission
  - Models/Voucher.swift: InRecycler carries recyclerMembers; drop VoucherPrivacyLevel/degraded readiness
  - Models/VoucherLocationUpdate.swift: write recyclerMembers
  - Services/VoucherLocation/VoucherLocationService.swift: carry RingStatus.included through to recyclerMembers; track all unsettled vouchers
  - Transfer/Readiness/ReadinessState.swift: delete .degraded; readiness becomes strategy-driven
  - Transfer/CoinSelection/CoinSelector.swift: verdict-aware selection via SpendScope; drop degraded ordering
  - Transfer/TransferPreview.swift: delete isDegraded / nonDegradedResult
  - ExternalPayment/Planner/ExternalPaymentPlanner.swift: filter on .spendable
  - ExternalPayment/Service/OffboardVouchersForPaymentService.swift: filter on .spendable
  - CoinageService.swift / CoinageService+make.swift: build + start evaluator; inject settings; drop recycle-at-start
  - CoinageConstants.swift: recycleAtAge stays only as the chain ceiling input; drop minimumRingSize
  # New — app target
  - polkadot-app/Common/Coinage/CoinageRecyclingStrategyStore.swift: new — settings impl over SettingsManager
  - polkadot-app/Common/Storage/UserDataModel.xcdatamodeld/UserDataModel45.xcdatamodel: new model version
  # Deleted
  - polkadot-app/Common/Coinage/CoinageRecyclingScheduler.swift: DELETED (BGProcessingTask path)
  - Models/VoucherPrivacyLevel (type): DELETED
must_not_touch:
  - Coin CoreData entity (nothing is persisted for coins — verdicts are derived)
  - SubstrateDataModel (only UserDataModel changes)
seams_used:
  - CoinRecyclingStrategyProtocol: the composition point — one parametric policy, two decorators
  - CoinRecyclingEvaluator: started from CoinageService.make(), app-process lifetime (foreground), like the existing sync services
  - SubstrateSdk.BigRational: fraction arithmetic (.percent(of:), mul(value:), BigUInt.sub(rational:))
  - DenominationBreakdownContext: cached exponent→planks conversion (valueInPlanks(for:) = unit << exponent), sync
  - SettingsManager: strategy persistence, injected from the app into the package
  - AsyncCurrentValueSubject / combineLatest / AnyAsyncSequence: reactive streams (AsyncExtensions)
new_types:
  - CoinRecyclingState: per-coin gate verdict. Derived, never persisted.
  - RecyclingParams: maxUnavailableBalance (BigRational) + minRecyclingAge (Int16) + requiredRingFill (BigRational) + allowsConfirmedSpend (Bool)
  - RecyclingStrategyType: user-chosen preset identity + params(forcedRecyclingAge:)
  - CoinRecyclingStrategyProtocol: the policy seam
  - RecyclingSnapshot: total + already-unavailable balance for one evaluation
  - VoucherUsabilityContext: ring capacities for the voucher predicate
  - RecyclingVerdicts: [DerivationIndex: CoinRecyclingState] for one tick
  - CoinBuckets / VoucherBuckets: pre-classification shared by the evaluator and balance
  - CoinageRecyclingStrategySettings: read/write the chosen preset
  - UnloadQuota / UnloadQuotaTracker: remaining + period limit, cached and incrementally maintained
  - SpendScope: .spendable | .withConfirmation — selection scope
risks:
  - Verdicts are recomputed rather than stored; every consumer must handle "not yet evaluated" (nullable subject; balance withholds first emission)
  - Deleting the BGProcessingTask removes background recycling; recycling now only runs while the app is alive (accepted)
  - The 5s tick retries a failing recycle with no backoff
  - estimateRemainingUnloadQuota over-reports if tokens consumed out of index order; bounded by full re-walk every 5 unloads + period boundary
  - MAX_PRIVACY recycles continuously by construction (unload mints age-1 successor); quota valve is load-bearing, not a corner case
  - Migration UserDataModel v44 -> v45 drops columns on the recycler voucher entity; migration test is the gate
  - Pre-existing: VoucherLocationService never clears a location, so an archived ring still reads InRecycler (not fixed here)
out_of_scope:
  - Privacy switch UI, strategy chooser, confirmed-spend confirmation sheet, enter-amount secondary amount, all copy/.xcstrings (stage 2)
  - Continuous interpolation between presets and the 2D parameter space (R2)
  - The continuous quota-pressure curve — only the hard safety valve lands here
  - Replacing hardcoded coinMaxAge = 16 with a chain read (also out-of-scope on Android; fetchMaxConsolidation exists but unwired)
open_questions: []
confirmed_facts:
  - Unload resets coin age to 1 (D17.6). On-chain pallet logic, so it holds identically for iOS — MAX_PRIVACY re-recycles its own age-1 successors by design; the quota valve is what bounds it.
---

## Goal

Replace the single hardcoded recycling rule (`recycleAtAge = coinMaxAge(16) − 2 = 14`) with a
user-chosen privacy strategy that decides both **when a coin goes into the recycler** and **which
coins and vouchers count as available**. The per-voucher `full/degraded` privacy quality is removed;
balance splits into **spendable**, **gainingPrivacy** (deliberately held back, optionally spendable
behind a confirmation), and **pending** (still arriving, or past the chain ceiling).

The strategy is a **preset of a two-parameter model**, not a bespoke policy per option, so a later
release can open intermediate points on the axis and then the full 2D parameter space without
rewriting the logic layer. Nothing hardcodes "three options" outside `RecyclingStrategyType`.

This is a port of the Android stage-1 logic layer (decisions D1–D20). Android decisions are locked;
this document records only the iOS-specific realisation.

## Approach

### The parameter model

Every coin gets a **gate** (should it recycle) and a **priority** (which acts first). Three
parameters drive it, with `N` = the forced-recycle age (`getCoinRecyclingAge()` = `coinMaxAge − 2` = 14):

- `maxUnavailableBalance` (`BigRational`) — the share of total balance acceptable to hold
  *unavailable* while recycling. A **ceiling**, not a target; it exists so more than one coin can
  recycle at once.
- `minRecyclingAge` (`Int16`) — the age below which recycling is not considered.
- `requiredRingFill` (`BigRational`) — the *exit* condition: how full the ring must be before a
  recycled voucher counts usable again. This is the knob that produces the spendability delay.
- `allowsConfirmedSpend` (`Bool`) — whether `gainingPrivacy` balance may be spent behind a
  confirmation.

Fractions use `SubstrateSdk.BigRational` (`.percent(of: 20)`, `rational.mul(value: balance)`,
`BigUInt.sub(rational:)`) — no new type is introduced.

```swift
struct RecyclingParams {
    let maxUnavailableBalance: BigRational
    let minRecyclingAge: Int16
    let requiredRingFill: BigRational
    let allowsConfirmedSpend: Bool
}

enum RecyclingStrategyType { case minPrivacy, balanced, maxPrivacy }

extension RecyclingStrategyType {
    func params(forcedRecyclingAge: Int16) -> RecyclingParams {
        switch self {
        case .minPrivacy:
            RecyclingParams(maxUnavailableBalance: .percent(of: 0),
                            minRecyclingAge: forcedRecyclingAge,
                            requiredRingFill: .percent(of: 0),
                            allowsConfirmedSpend: true)   // gainingPrivacy is always empty, so it never applies
        case .balanced:
            RecyclingParams(maxUnavailableBalance: .percent(of: 20),
                            minRecyclingAge: max(minRecyclableAge, forcedRecyclingAge / 3), // = 4
                            requiredRingFill: .percent(of: 50),
                            allowsConfirmedSpend: true)
        case .maxPrivacy:
            RecyclingParams(maxUnavailableBalance: .percent(of: 100),
                            minRecyclingAge: minRecyclableAge, // = 1
                            requiredRingFill: .percent(of: 100),
                            allowsConfirmedSpend: false)
        }
    }
}

private let minRecyclableAge: Int16 = 1  // unload mints its successor at age 1
```

`minPrivacy`'s zero budget never voluntarily gates; the chain-limits decorator alone forces coins at
`N`, reproducing today's behaviour — which is why it is the default.

`maxPrivacy` gates at **1, not 0**, because unload sets the successor's age to 1. A recycled coin
therefore produces a successor immediately eligible again, and the recycler loads it straight back.
**Intended, not a convergence failure** — it means max privacy leans on the quota valve continuously.
Unload-resets-age-to-1 is on-chain pallet logic (D17.6), so it holds identically for iOS; the quota
valve is what bounds the resulting churn.

**A coin with unknown age must never be gated.** Two guards: (1) `preClassifyCoins` filters to
`minted` (`isFree && isOnchain && age != nil`) before evaluation; (2) the strategy compares
`coin.age` and a nil/unknown age fails every `age >= minRecyclingAge` test. A test pins the behaviour.

### The policy seam

One protocol in `Recycling/Strategy/` (public package api), following the `UnloadDelayStrategy`
precedent. Value conversion uses the **cached** `DenominationBreakdownContext` — `valueInPlanks(for:)
= unit << exponent` is a pure sync lookup, so `evaluate` is **synchronous**.

```swift
protocol CoinRecyclingStrategyProtocol: Sendable {
    func evaluate(coins: [Coin], snapshot: RecyclingSnapshot,
                  context: DenominationBreakdownContext) -> RecyclingVerdicts
    func isVoucherUsable(_ voucher: Voucher, context: VoucherUsabilityContext) -> Bool
    func allowsConfirmedSpend() -> Bool
}

struct RecyclingSnapshot: Equatable, Sendable {
    let total: Balance        // free coins + free vouchers
    let unavailable: Balance  // pending before this pass gates anything
}

enum CoinRecyclingState: Sendable {
    case mustRecycle   // past the age the chain accepts → pending, never offered
    case toRecycle     // the policy's own choice → gainingPrivacy, may be offered
    case allowUse      // spendable
}

typealias RecyclingVerdicts = [DerivationIndex: CoinRecyclingState]
```

The single policy walks coins **oldest-first** (nearest the ceiling has most to lose), and the budget
test is **headroom, not fit** — a coin is admitted whenever *any* budget remains and may overshoot.
A strict `unavailable + amount <= budget` would mean a coin worth more than the budget could never
recycle voluntarily (any coin over a fifth of balance under `balanced`), so it would sit until the
forced age. `minPrivacy` is unaffected: `unavailable < 0` is never true, so a zero budget admits
nothing.

```swift
struct ParametricRecyclingStrategy: CoinRecyclingStrategyProtocol {
    let params: RecyclingParams

    func evaluate(coins: [Coin], snapshot: RecyclingSnapshot,
                  context: DenominationBreakdownContext) -> RecyclingVerdicts {
        let budget = params.maxUnavailableBalance.mul(value: snapshot.total)
        var unavailable = snapshot.unavailable
        var verdicts: RecyclingVerdicts = [:]
        for coin in coins.sorted(by: { ($0.age ?? -1) > ($1.age ?? -1) }) {
            let age = coin.age ?? -1
            let gated = age >= params.minRecyclingAge && unavailable < budget
            if gated { unavailable += context.valueInPlanks(for: coin.exponent) }
            verdicts[coin.derivationIndex] = gated ? .toRecycle : .allowUse
        }
        return verdicts
    }

    func isVoucherUsable(_ voucher: Voucher, context: VoucherUsabilityContext) -> Bool {
        guard voucher.isInRecycler else { return false }
        let capacity = context.capacity(for: voucher.exponent)
        let required = params.requiredRingFill.ceilMul(capacity)     // ceiling
        let ringFilled = voucher.recyclerMembers ?? 0 >= required
        // below a full ring the random unload delay substitutes for anonymity-set size;
        // at 100% nothing but a full ring will do
        let delayElapsed = params.requiredRingFill < .percent(of: 100) && voucher.readyAt < .now
        return ringFilled || delayElapsed
    }

    func allowsConfirmedSpend() -> Bool { params.allowsConfirmedSpend }
}
```

### Two decorators

The age ceiling and the quota valve are chain facts, wrapped rather than restated. Composition order
is fixed and the chain is rebuilt **per evaluation** because `quotaExhausted` moves.

`EnsureChainLimitsStrategy` — any coin at `age >= forcedRecyclingAge` becomes `.mustRecycle`
regardless of the inner verdict, **bypassing the budget**. This is what lets `minPrivacy` carry a
zero budget without stranding old coins. `.mustRecycle` (not `.toRecycle`) so a chain-forced coin is
never offered for a confirmed spend.

`EnsureQuotaLimitsStrategy` — when free-unload quota crosses the reserve, returns an **empty** map;
the chain-limits decorator above then fills every unmapped coin with `.allowUse` except the forced
ones — "only recycle coins that must." Quota is never surfaced (it can't be topped up), so it is
auto-managed.

Both decorators delegate `isVoucherUsable` and `allowsConfirmedSpend` untouched, so **balance uses a
bare `ParametricRecyclingStrategy`** for voucher classification, needing no quota read.

```swift
struct RecyclingStrategyProvider {
    let coinageConstants: CoinageConstantsProviding
    let quotaTracker: UnloadQuotaTracker

    func strategy(for type: RecyclingStrategyType, chainId: ChainModel.Id) async throws
        -> CoinRecyclingStrategyProtocol {
        let forced = coinageConstants.forcedRecyclingAge
        let quota = try await quotaTracker.remaining(chainId: chainId)
        let exhausted = quota.remaining <= quotaReserve.mul(value: BigUInt(quota.limit))
        return EnsureChainLimitsStrategy(
            inner: EnsureQuotaLimitsStrategy(
                inner: ParametricRecyclingStrategy(params: type.params(forcedRecyclingAge: forced)),
                quotaExhausted: exhausted),
            forcedRecyclingAge: forced)
    }

    func voucherStrategy(for type: RecyclingStrategyType) -> CoinRecyclingStrategyProtocol {
        ParametricRecyclingStrategy(params: type.params(forcedRecyclingAge: coinageConstants.forcedRecyclingAge))
    }
}

private let quotaReserve: BigRational = .percent(of: 20)
```

### Reading remaining quota

iOS already has `UnloadTokenPeriodCalculator` and `ConsumedTokenChecker` under
`Transfer/UnloadToken/`. Add a **counting** reader — the existing resolver only answers "can I
satisfy N" and short-circuits, so it never counts what's left.

```swift
struct UnloadQuota { let remaining: Int; let limit: Int }

protocol UnloadQuotaTracker: Sendable {
    func remaining(chainId: ChainModel.Id) async throws -> UnloadQuota
    func noteUnloadHappened()
}
```

Walk counter batches, **stop at the first batch whose last counter is free**, treat the remainder as
free — `O(consumed / batch)`, cheap when the limit is large. Exact while tokens are consumed in index
order (which the resolver does); otherwise **over-reports remaining**, which only makes the valve
engage *later* — fail-safe. Cache for the current period (`UnloadTokenPeriodCalculator`);
`noteUnloadHappened` decrements, **every fifth call re-walks** to bound drift, and the period boundary
invalidates. `QUOTA_RESERVE = 20%` of the period limit (a fraction, so it scales with the chain's
allowance).

### Pre-classification: shared by the evaluator and by balance

The verdict is recomputed on a 5-second throttle, but **balance must stay real-time** — a spend must
drop displayed balance at once. The two cannot share an output; they share the *pure classification
underneath* and differ only in what they do with it.

```swift
func preClassifyCoins(_ coins: [TrackedCoin]) -> CoinBuckets
    // free (denominator) / minted (isFree && isOnchain && age != nil → gate-eligible) / minting
func preClassifyVouchers(_ vouchers: [TrackedVoucher],
                         strategy: CoinRecyclingStrategyProtocol,
                         context: VoucherUsabilityContext) -> VoucherBuckets
    // free / usable / gainingPrivacy (in recycler, not yet usable) / minting
```

The **evaluator** builds the snapshot from both and produces coin verdicts:

```swift
let coinBuckets = preClassifyCoins(coins)
let voucherBuckets = preClassifyVouchers(vouchers, strategy: bareStrategy, context: usabilityContext)
let snapshot = RecyclingSnapshot(
    total: value(coinBuckets.free, context) + value(voucherBuckets.free, context),
    unavailable: value(coinBuckets.minting, context)
        + value(voucherBuckets.minting, context)
        + value(voucherBuckets.gainingPrivacy, context))
let verdicts = strategy.evaluate(coins: coinBuckets.minted, snapshot: snapshot, context: context)
```

**Balance** runs the same two pre-classifiers on every emission and applies only the *coin verdicts*:

```swift
let (toRecycle, allowUse) = coinBuckets.minted.partition { verdicts[$0.derivationIndex] == .toRecycle }
let mustRecycle = coinBuckets.minted.filter { verdicts[$0.derivationIndex] == .mustRecycle }
spendable      = value(allowUse, ctx) + value(voucherBuckets.usable, ctx)
gainingPrivacy = value(toRecycle, ctx) + value(voucherBuckets.gainingPrivacy, ctx)
pending        = value(coinBuckets.minting, ctx) + value(voucherBuckets.minting, ctx) + value(mustRecycle, ctx)
```

A settled coin absent from the verdict map buckets as **pending**, not spendable — the follow-up
correction is upward; a spendable→gainingPrivacy flicker would visibly drop balance a moment after
showing it.

### The evaluator — derived state, on a throttle

`CoinRecyclingEvaluator` is a started actor in the shape of existing sync services, launched from
`CoinageService.make()` on the app-process scope (foreground lifetime). iOS has **no generic
`throttleLatest`** async operator, so add a small leading-edge throttle utility (conflate, then
emit-and-delay) and put it **before** the work, not after.

```swift
actor CoinRecyclingEvaluator {
    private let subject = AsyncCurrentValueSubject<RecyclingVerdicts?>(nil)  // nil until first evaluation
    var verdicts: AnyAsyncSequence<RecyclingVerdicts> { subject.compactMap { $0 }.eraseToAnyAsyncSequence() }

    func start() {
        task = Task {
            let inputs = combineLatest(timerTick(interval: .seconds(5)), coinsStream, vouchersStream, strategyStream)
            for await _ in inputs.throttleLeadingEdge(.seconds(5)) {
                guard let result = try? await evaluate() else { continue }
                subject.send(result)
                await recycleGated(result)   // from the loop body, NOT a subject observer
            }
        }
    }

    private func recycleGated(_ verdicts: RecyclingVerdicts) async {
        let gated = verdicts.filter { $0.value == .toRecycle || $0.value == .mustRecycle }.keys
        guard !gated.isEmpty else { return }
        // recyclingService drops non-idle coins, so the 5s cadence is idempotent, not duplicative
        if await recyclingService.recycle(coinsFor(gated)) { quotaTracker.noteUnloadHappened() }
    }
}
```

The timer tick is load-bearing twice: it arms `balanced`'s `readyAt`/`delayUnloadUntil` exit without
an external event, and it guarantees a re-emission every 5s — the retry path now that the scheduler is
gone. `recycleGated` runs from the `collect` body, **not** a subject observer:
`AsyncCurrentValueSubject` suppresses equal values, so a retry after a failed recycle (identical map)
would never reach an observer. Balance still wants dedup, so balance observes the subject.

`evaluate()` is where the async work lives: it resolves the decorated strategy (which reads the quota
estimate) and the ring capacities, reads the **cached** denomination context, runs both
pre-classifiers, and calls `strategy.evaluate` on `coinBuckets.minted`.

### Recycling service — refactor, not delete

`CoinageRecyclingService` keeps only **submission**. Delete `fetchEligibleCoins()`, the age filter,
and `scheduleRecycling()`/`ensureScheduled()`; keep the idle/idempotency guard (skip coins whose
ledger state isn't free). It becomes an injectable `recycle(_ coins:) async -> Bool` the evaluator
calls. `CoinageRecyclingScheduler` (BGProcessingTask) and the recycle-at-app-start call are deleted.

Consequences (accepted): recycling runs only while the app is alive — a coin crossing the forced age
with the app closed recycles on next launch. Retry has no backoff — the 5s tick re-attempts.

### Balance

```swift
struct CoinageBalance {   // reshaped
    let spendable: Balance
    let gainingPrivacy: GainingPrivacy
    let pending: Balance
    struct GainingPrivacy { let amount: Balance; let canSpendWithConfirmation: Bool }
    var available: Balance { gainingPrivacy.canSpendWithConfirmation ? spendable + gainingPrivacy.amount : spendable }
    var total: Balance { spendable + gainingPrivacy.amount + pending }
}
```

`canSpendWithConfirmation` = `strategy.allowsConfirmedSpend()`. `CoinageBalanceService` keeps its own
timestamp tick and subscriptions (voucher usability depends on `readyAt < now`), observes
`evaluator.verdicts`, and withholds its first emission until a verdict lands (no zero-flash).

### Selection & SpendScope

A single `CoinageAssetSelector` answers every scope from one wallet read, keyed by
`SpendScope { .spendable, .withConfirmation }`. Invariants (both tested): `.mustRecycle` is absent
from every answer; `.withConfirmation` cannot override the strategy (under `maxPrivacy` it equals
`.spendable`).

| caller | scope |
|---|---|
| `CoinSelector` / prepare-transfer | `.spendable`, then `.withConfirmation` (narrow-first, fall back) |
| `ExternalPaymentPlanner` | `.spendable` |
| `OffboardVouchersForPaymentService` | `.spendable` |

`TransferPreview.isDegraded` / `nonDegradedResult` are deleted; the secured-then-degraded preference
is restored at plan granularity via narrow-first-then-fallback.

### Vouchers, ring capacity & persistence

`Voucher`'s in-recycler state gains `recyclerMembers` (carries `RingStatus.included`, the provable
anonymity set — not `total`). `VoucherLocationService` already reads this and discards it; carry it
through and widen its input to all unsettled vouchers. Ring capacity = `2^exponent − 257` (257 =
ring-VRF PIOP overhead); recycler rings are `R2e10` → **767 members**. `RingCapacityProvider`
memoises it per denomination. The threshold becomes `requiredRingFill` of real capacity, replacing
the hardcoded `minimumRingSize = 10`. `VoucherPrivacyLevel` and `ReadinessState.degraded` are deleted.

**CoreData migration UserDataModel v44 → v45.** The recycler-voucher entity lives in `UserDataModel`
(currently `UserDataModel44.xcdatamodel`). Add model version v45 and bump `.xccurrentversion`. Change
only that entity: `+recyclerMembers: Int?`, drop the privacy/degraded-readiness fields. The coin
entity is untouched. Adding an optional attribute + dropping attributes is lightweight-migration
eligible; preserve locations and `allocatedAt`; no backfill.

### Settings

```swift
protocol CoinageRecyclingStrategySettings: Sendable {
    func strategyStream() -> AnyAsyncSequence<RecyclingStrategyType>
    func current() -> RecyclingStrategyType
    func set(_ type: RecyclingStrategyType) async throws
}
```

Impl lives app-side (`CoinageRecyclingStrategyStore`) over `SettingsManager` (key
`coinageRecyclingStrategy`, app-wide, default `.minPrivacy`), injected into the package via
`CoinageService.make()` per the "inject dependencies from the outside" rule. `set` writes and returns;
the strategy stream is a `combineLatest` input to the evaluator, so the whole active set re-gates on
the next tick (≤5s) with no un-triaged intermediate state.

## Step-by-step

1. **Foundations.** Reuse `SubstrateSdk.BigRational` for fractions. Add `CoinRecyclingState`,
   `RecyclingParams`, `RecyclingStrategyType` + `params(forcedRecyclingAge:)`, `RecyclingSnapshot`,
   `VoucherUsabilityContext`, `RecyclingVerdicts`, `CoinBuckets`/`VoucherBuckets`. Pure value types.
2. **Policy + decorators.** `ParametricRecyclingStrategy`, `EnsureChainLimitsStrategy`,
   `EnsureQuotaLimitsStrategy`, `RecyclingStrategyProvider`.
3. **Pre-classifiers.** `preClassifyCoins`/`preClassifyVouchers`. Test before wiring.
4. **Quota reader.** `UnloadQuota` + `UnloadQuotaTracker` on `ConsumedTokenChecker`; `QUOTA_RESERVE`,
   every-5 re-walk, period invalidation.
5. **Ring capacity + voucher members.** `RingCapacityProvider` (`2^exp − 257`); carry
   `RingStatus.included` through `VoucherLocationService` into `recyclerMembers`; CoreData v44→v45 +
   migration test.
6. **Settings seam.** `CoinageRecyclingStrategySettings` in the package; `CoinageRecyclingStrategyStore`
   over `SettingsManager`; inject via `CoinageService.make()`.
7. **Evaluator.** `CoinRecyclingEvaluator` actor: combine + 5s throttle-before-work; verdict subject
   (`compactMap` first non-nil); `recycleGated` from the loop body. Wire `start()` into `make()`.
8. **Balance reshape.** Three-bucket `CoinageBalance`; `CoinageBalanceService` onto pre-classifiers +
   verdicts, keeping its own tick; withhold first emission.
9. **Selection.** `CoinageAssetSelector` + `SpendScope`; move `CoinSelector`,
   `ExternalPaymentPlanner`, `OffboardVouchersForPaymentService` onto verdict-aware selection; delete
   degraded ordering/preview.
10. **Recycling service refactor.** Strip decision/scheduling from `CoinageRecyclingService`; keep
    submission + idle guard behind `recycle(_:)`; add the missing tests; wire to `recycleGated`.
    Delete `CoinageRecyclingScheduler` + BGProcessingTask registration + recycle-at-start.
11. **Cleanup.** Remove `VoucherPrivacyLevel`, `ReadinessState.degraded`, `minimumRingSize`, dead
    degraded confirmation surfaces. Compile the app; fix consumers of the old balance model.

## Verification plan

Swift Testing (`@Test`/`#expect`). **Package tests run from the main-target test plan**, so put
pure-logic tests in `Packages/Coinage/Tests`; reserve `polkadot-appTests` for tests that need a real
CoreData stack (the migration test).

- `ParametricRecyclingStrategyTests` — per preset (min gates nothing even with old coins; max gates
  from age 1; balanced gates `age >= 4` until budget spent); zero-total; overshoot admitted, the coin
  after it is not; **unknown-age never gated under every preset** (assert behaviour, not the sentinel).
- Voucher usability matrix — `recyclerMembers × readyAt` per preset; max ignores an elapsed delay; min
  usable at zero members.
- `EnsureChainLimitsStrategy` / `EnsureQuotaLimitsStrategy` — forced-at-ceiling passthrough (as
  `.mustRecycle`); under exhaustion only forced coins survive.
- `CoinagePreClassification` — `minted`/`minting` partition `free` exactly; on-chain unknown-age →
  minting; voucher buckets partition with no overlap.
- `CoinRecyclingEvaluator` — verdicts recompute on strategy change; recycle fires on an *unchanged*
  map (the dedup trap); at most one evaluation per interval under a burst (throttle-before-work).
- `UnloadQuotaTracker` — stops at first free tail + adds remainder; fully-consumed → zero;
  `noteUnloadHappened` decrements; fifth call re-walks; period change invalidates.
- Balance — three-bucket mapping; **reacts to a spend without waiting for a new verdict**; no emission
  before first verdict; settled coin absent from map → pending.
- `CoinageAssetSelector` — `.mustRecycle` never returned; `.withConfirmation` == `.spendable` under
  max privacy.
- `CoinageRecyclingService` (new coverage) — only idle coins submitted; a failed submit surfaces so
  the next tick retries; empty input is a no-op.
- Migration — voucher rows survive with locations + `allocatedAt`; column change applied
  (`polkadot-appTests`, real CoreData).
- Manual — default unchanged over an existing build; switch to max, watch balance move to
  gaining-privacy and recycling start within 5s; see an age-1 successor picked up again; switch back
  with no zero-flash.

## North-star alignment

Privacy stops being a per-voucher quality attached to a spend and becomes a policy the user selects
and the balance reflects. The parametric model is the north-star-facing part: R2 opens intermediate
points on the `(maxUnavailableBalance, minRecyclingAge)` axis and then the full 2D space, on a
polynomial/log scale. Nothing hardcodes "three options" outside `RecyclingStrategyType`.
