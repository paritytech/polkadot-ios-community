---
task: Refactor Transfer flow to TrackedCoin/TrackedVoucher + Android parity (mint-before-op, register+track, two-phase handoff)
date: 2026-08-27
status: in_progress
delivery: Phase 0 first, gated on a green build before Phase 2/3
products_payment: AUDITED — claim/receive only (transferCoinsFromSecretKeys, claiming coins a
  peer sent us). No outgoing handoff → OUT OF SCOPE for two-phase handoff. Only outgoing origin
  is TransferAmountInteractor.executeTransfer → sendTransfer → chat / W3SPay.
phase_3_delivery: Option A staged — (stage 1) memo-after-prepare relocation + two-phase handoff;
  (stage 2) promote CoinageTransaction to allocate + collapse TransferPlanFactory allocation.
phase_3_step1a: DONE — build green. Additive two-phase handoff FOUNDATION (nothing calls it yet,
  behavior unchanged): CoinageStoreTransaction + CoinageTransactionContext.Transaction gained
  markHandoffPending/commitHandoff/releaseUncommittedMarks (writes CoinHandoffMark .pending/
  .committed/.none; insertMark still writes .committed). DurabilityStoring +
  DurabilityCoreDataStore gained markHandoffPending/commitHandoffs/releaseUncommittedHandoffs.
  New CoinageHandoffCommit protocol + StoreHandoffCommit. DurabilityServicing/DurabilityService
  gained preCommitHandoff(assets) -> CoinageHandoffCommit and releaseUncommittedHandoffs().
phase_3_step1b: DONE — build green. TransferStrategy.run -> prepare(context) -> PreparedStrategy
  {handoffCommit, submit}. TransferContext.handOff replaced by preCommitHandoff(coins) -> handle.
  All 3 strategies rewritten: register/insertOutputs/preCommit in foreground prepare, extrinsic
  submission in background submit closure. Recipient/destination coins now handed off PRE-submit
  (fixes the post-success window). execute(): prepare foreground -> spawn submit background ->
  BRIDGE commit() -> return memo. Bridge keeps handoff final immediately (≈ today) until the
  transport commits in step (e). Behavior change is live: handoff tied to memo-prepared, not
  submit-success; on split/unload failure the durability layer releases the consumed input.
phase_3_stage1: DONE — build green. Two-phase handoff wired end to end, bridge removed.
  (d) new PreparedTransfer{memo, handoffCommit}; TransferSenderServicing.execute + CoinageServicing
  .executeTransfer return it. (e) TransferAmountInteractor.confirmCoinageTransfer commits the
  handle AFTER sendTransfer (covers chat + W3SPay via TransferSubmitting); a FATAL send failure
  throws with the handle uncommitted so a relaunch returns the coins; non-fatal proceeds + commits
  (matches prior "proceed unless fatal"). (f) ServiceCoordinator releases uncommitted handoffs on
  launch before durabilityService.start().
  Refinement (optional, deferred): commit INSIDE the transport's durable write (chat message row /
  W3sPaymentRecord) instead of after sendTransfer returns — closes a tiny crash window between
  send-returns and commit. Android does the in-transaction commit.
phase_3_stage2: DONE — build green. CoinageTransaction is now a class that ALLOCATES:
  mintCoins(exponents) allocates via CoinAllocator + records outputs, created by
  CoinageTransactionFactory (concrete) conforming to CoinageTransactionFactoryProtocol. Strategies
  carry DENOMINATIONS (not pre-allocated coins) + the factory, and mint in prepare. prepare returns
  PreparedStrategy.memoEntries; execute builds the memo AFTER prepare from those. TransferPlanFactory
  no longer allocates or builds memos (dropped allocateCoins/allocateCoinsPerGroup); TransferPlan is
  now just { strategy } (dropped dead plannedMemoEntries + claimTokensRequired). make builds the
  transaction factory from CoinAllocator. Full Android shape: mint-and-collect in one place.
phase_3_submission_rework: DONE — build green. Collapsed durability register + submitRegistered
  into a single fire-and-forget submit (Android shape). DurabilityServicing now:
  - submit(inputs:outputs:builder:origin:) async throws -> Void: registers (claims inputs), then
    tracks the extrinsic in a background Task; returns after registration, does NOT await inclusion.
  - submitAwaitingOutcome(...) -> DurabilitySubmission: the old blocking behavior, kept for
    recycling + offboard which act on the outcome synchronously (renamed from submit).
  - REMOVED register / submitRegistered / abandon (were only used by the two transfer strategies).
  Split + Unload strategies now call one submit in prepare (unload moved its network prep —
  blockHash/origins/revisions — into prepare, foreground, then fire-and-forget submits per group;
  build-all-then-submit-all). No background submit closure (PreparedStrategy.submit just settles).
  Semantic change (matches Android): the send waits for prep, not inclusion; status resolves via
  the SubmissionWatcher (background) + RecoveryPass; inputs are claimed when submit registers.
cleanup_item1: DONE — build green. Removed the dead Voucher.localState projection.
  - Voucher model: dropped localState property, the State enum, withLocalState (CDVoucher already
    dropped the column, so it was always .available — dead).
  - DROPPED ProjectionReconciler entirely (its only job was materializing voucher localState;
    the remaining spent/failed voucher deletes are unnecessary — those vouchers derive-on-read
    exactly like spent coins). RecoveryPass no longer reconciles; make no longer builds it.
  - VoucherService: removed markAvailable/markPendingTransfer/markPendingOnboarding; fetchAvailable
    InRecycler drops the always-true localState filter.
  - Callers updated: CoinageRecyclingService (save voucher as-is), ExternalPaymentPlanner (drop
    no-op filter), ExternalPaymentTransferContext (save/reserve no longer write localState),
    TransferContext.reserve is now a no-op (item 3 removes it).
cleanup_item2: DONE — build green. Allocators persist on mint: CoinAllocator/VoucherAllocator now
  take the coin/voucher repository and save inside allocate() (index source is a persistent counter
  in CoinIndexstore, not MAX; actor isolation serialises the read-modify-write). ONE shared allocator
  per Coinage instance (was two CoinAllocator instances in make — a real race on the shared counter);
  no explicit Mutex needed (actor). Redundant explicit saves in recycling/offboard/loader are now
  harmless upserts (minor cleanup left).
cleanup_item3: DONE — build green. DELETED TransferContext. Strategies now mint (persisted by the
  allocator), fire the background-tracked durability.submit, and call durability.preCommitHandoff
  directly — no reserve/insertOutputs/settle. TransferStrategy.prepare() takes no context;
  PreparedStrategy dropped its submit closure; TransferSenderService.execute has no background Task
  and no context; CoinageService.executeTransfer builds no context. The recovery pass is driven by
  the SubmissionWatcher's onRelease (conditional, Android-style); exact-match needs none (handoff
  mark write triggers the balance CoreData stream). No local projection layer remains — matches
  Android (allocate-and-save + derive-on-read from the ledger).
bg_executor_move: DONE — build green. Moved backgroundExecutor from TransferSenderService into
  SubmissionWatcher. New SubmissionWatcher.watch(entryId:builder:origin:) launches the detached
  submission task wrapped in backgroundExecutor.execute { markStallActivity { markStallRegion {...}}},
  so the fire-and-forget submission holds an OS background-task assertion for its full inclusion wait
  (the fire-and-forget rework had dropped this — a real regression, now fixed). DurabilityService.submit
  delegates to watcher.watch. TransferSenderService no longer takes backgroundExecutor.
  Swept: removed redundant allocator-vs-caller saves in CoinageRecyclingService.prepareRecycle and
  VoucherService.load (allocator persists on mint now).
  Left (harmless, cascades into external-payment internals): offboard savePendingOnboarding double-save;
  ExternalPaymentTransferContext.process newVouchers param + GroupSuccess.newVouchers.
STATUS: Phases 0,1,2,3 COMPLETE + cleanup item 1 done, all green. Deferred: tests; CoinageAssetsService
  consolidation (memory); optional in-transaction handoff commit (chat/W3SPay).
phase_0: DONE — build green 2026-08-27. Extra consumers found beyond the plan list:
  VoucherService (fetchAllTracked + tracked repo), CoinStateSyncService (tracked provider),
  DurabilityCoreDataStore.handedOffCoinModels (handoffMark), AssetDetails module x4
  (ViewFactory/Interactor/Presenter/Protocols → TrackedCoin/TrackedVoucher).
  Recycling parity fix: TrackedCoin.isAwaitingRecycling(for recycleAtAge: Int16 =
  CoinageConstants.recycleAtAge) — now a defaulted func (state.isFree && isOnchain &&
  age >= recycleAtAge). Balance service uses the default; CoinageRecyclingService passes its
  injected recycleAtAge. Closes the isOnchain gap and centralizes the predicate.
phase_1: DONE — verified preview→execute is tracked end-to-end (previewTransfer +
  debug fetchers + externalPayment all route through the tracked fetch path).
phase_2: DONE — build green. Design note: CoinageTransaction is a COLLECTOR, not an
  allocator (consume/use/mint/handOff -> CoinageTransactionAssets{inputs,outputs,outputCoins,
  handedOff}). Allocation stays at plan time (TransferPlanFactory) because iOS builds the memo
  BEFORE run(); moving minting into the builder is deferred to Phase 3 (memo-after-run). So the
  planned Factory+allocator injection was NOT needed. Refactored SplitCoinStrategy +
  UnloadIntoCoinsStrategy to declare register inputs/outputs via the builder; ExactMatch has no
  entry so left as-is. TransferContext/TransferPlanFactory untouched. Timing identical.
parity_backlog: Android centralizes tracked/selectable fetch in ONE CoinageAssetsUseCase
  (getSelectableCoins/getSelectableVouchers → raw). iOS scattered it across CoinService/
  VoucherService + call sites. Future: introduce CoinageAssetsService to consolidate.
  Also iOS-only vs Android: recoverSpentCoins flow (Android has none), chain-sync structure.
files_touched:
  # Phase 0 — compile prereq (finish deferred selection migration)
  - Packages/Coinage/Sources/CoinService.swift
  - Packages/Coinage/Sources/DatabaseDependencyFactoring.swift
  - polkadot-app/Modules/TransferAmount/Model/CoreData/CoinageDatabaseDependencyFactory.swift
  - Packages/Coinage/Sources/CoinageService+make.swift
  - Packages/Coinage/Sources/CoinageService.swift
  - Packages/Coinage/Sources/Transfer/CoinSelection/CoinSelector.swift
  - Packages/Coinage/Sources/ExternalPayment/Planner/ExternalPaymentPlanner.swift
  - Packages/Coinage/Sources/Recycling/CoinageRecyclingService.swift
  # Phase 2 — CoinageTransaction builder
  - Packages/Coinage/Sources/Transfer/CoinageTransaction.swift            # NEW
  - Packages/Coinage/Sources/Transfer/RealCoinageTransaction.swift        # NEW
  - Packages/Coinage/Sources/Transfer/TransferContext.swift
  - Packages/Coinage/Sources/Transfer/Plan/TransferPlanFactory.swift
  - Packages/Coinage/Sources/Transfer/Plan/Strategies/ExactMatchStrategy.swift
  - Packages/Coinage/Sources/Transfer/Plan/Strategies/SplitCoinStrategy.swift
  - Packages/Coinage/Sources/Transfer/Plan/Strategies/UnloadIntoCoinsStrategy.swift
  # Phase 3 — two-phase handoff
  - Packages/Coinage/Sources/Transfer/CoinageHandoffCommit.swift          # NEW
  - Packages/Coinage/Sources/Durability/Engine/DurabilityService.swift
  - Packages/Coinage/Sources/Durability/Store/DurabilityStoring.swift
  - Packages/Coinage/Sources/Transfer/TransferSenderService.swift
  - Packages/Coinage/Sources/CoinageService.swift
  - polkadot-app/Modules/TransferAmount/TransferAmountInteractor.swift
  - polkadot-app/Modules/TransferAmount/TransferSubmitting.swift
  - polkadot-app/Modules/Chat/Helpers/LocalMessageCreatingOperationFactory.swift
  - polkadot-app/Modules/W3SPay/Services/W3sStatementSubmitter.swift
  - polkadot-app/Common/Services/ServiceCoordinator+Coinage.swift
seams_used:
  - DatabaseDependencyFactoring (app → package repository injection)
  - CoinageServicing.executeTransfer (package → app transfer entry point)
  - DurabilityServicing / DurabilityStoring (handoff mark persistence)
  - TransferSubmitting (app transport routing: chat / W3SPay)
must_not_touch:
  - Durability engine internals beyond adding preCommit/commit/release (registrar, watcher, RecoveryPass, ProjectionReconciler)
  - UserDataModel43 CoreData schema — no change needed (CDCoin.handoffMark is already Int16, covers .pending=1/.committed=2)
  - CoinageBalanceService bucketing (already refactored to predicates)
out_of_scope:
  - groupId batching for unload entries (decision: skip)
  - Threading TrackedCoin THROUGH strategies (Android keeps raw Coin/Voucher post-selection; we match that)
  - Products payment path if it constructs TransferMemo directly (audit; may not carry a handoff handle)
  - Tests (deferred by user earlier; add after the three phases land)
---

## Goal

Bring the iOS coinage Transfer flow to parity with Android on three axes, reusing the
already-landed `TrackedCoin`/`TrackedVoucher` model: (1) mint recipient+change assets before
submission, (2) register durability entries and track them on submission, (3) two-phase handoff
(provisional pre-commit → commit when the carrying memo is durable). #1 and #2 are already
satisfied behaviorally; the substance is #3 plus a `CoinageTransaction` builder to unify
mint/consume/handoff, and finishing the selection migration so the module compiles.

## Approach

- **Selection boundary only** carries the durability overlay. `previewStrategy` already takes
  `[TrackedCoin]`/`[TrackedVoucher]`; `CoinSelector` filters on `isSelectable`; strategies keep
  running on raw `Coin`/`Voucher` (matches Android — the overlay is consumed at selection, not
  re-derived downstream).
- **`CoinageTransaction` builder** (Android's `RealCoinageTransaction`) collects `inputs` /
  `outputs` / `handedOff` as a strategy declares "consume this, mint that, hand these off",
  replacing per-strategy hand-assembly of `register(inputs:outputs:)` + `insertOutputs` + `handOff`.
- **Two-phase handoff**: `preCommitHandoff` writes `CoinHandoffMark.pending` and returns a
  `CoinageHandoffCommit`; `commit()` promotes to `.committed`; `releaseUncommittedHandoffs()` on
  launch clears any `.pending` marks (payments that never became durable). `executeTransfer`
  returns `(memo, handoffCommit)`; each transport calls `commit()` inside its durable write.
- **Keep durability submission/tracking untouched.** To return the handle early without touching
  the watcher contract, split strategy execution into a foreground `prepare` (mint → register →
  insertOutputs → preCommit → build memo) and the existing background submit+settle.

## Steps

### Phase 0 — Finish selection migration (compile prereq)

1. **`CoinService`**: inject `AnyDataProviderRepository<TrackedCoin>`; add
   `fetchAllTrackedCoins() async throws -> [TrackedCoin]`.
2. **`DatabaseDependencyFactoring` + `CoinageDatabaseDependencyFactory`**: add
   `makeTrackedCoinRepository() -> AnyDataProviderRepository<TrackedCoin>` (mirror
   `makeCoinRepository`, using `TrackedCoinMapper`).
3. **`CoinageService+make`**: pass the tracked repository into `CoinService`.
4. **`CoinageService`**:
   - `previewTransfer` → fetch via `fetchAllTrackedCoins()` and pass `[TrackedCoin]` to `previewStrategy`.
   - `recoverSpentCoinsOnChain` → `fetchAllTrackedCoins().filter { $0.state.isConsumed }.map(\.coin)`.
5. **`CoinSelector`**: after `input.coins.filter { $0.isSelectable }`, map to `[Coin]` for the
   solver; replace the undefined `isExpiringSoon` reference with `isAwaitingRecycling`
   (note: `isSelectable` already excludes aged coins, so the clause is likely redundant — drop if so).
6. **`ExternalPaymentPlanner`**: `fetchAllTrackedCoins().filter { $0.isSelectable }.map(\.coin)`
   (replaces `.state == .available`).
7. **`CoinageRecyclingService.fetchEligibleCoins`**: `fetchAllTrackedCoins().filter { $0.state.isFree && aged }.map(\.coin)`
   (recycling wants free-but-aged, i.e. `isFree`, NOT `isSelectable`).
8. Build → module compiles green.

### Phase 2 — CoinageTransaction builder

1. **`CoinageTransaction.swift`** (NEW): protocol + `CoinageTransactionAssets(inputs, outputs, handedOff)`.
   Methods: `mintCoins`, `mintVoucher`, `consumeCoins`, `consumeReceivedCoin`, `useVouchers`,
   `handOff`, `build()`. Plus a `Factory`.
2. **`RealCoinageTransaction.swift`** (NEW): allocates via `CoinAllocator`/`VoucherAllocator`,
   accumulates `inputs`/`outputs`/`handedOff`. Minting = allocate + append output ref; persistence
   of the coin rows stays with `context.insertOutputs` (keep the explicit save).
3. **`TransferPlanFactory`**: inject the transaction factory so strategies receive it.
4. **Refactor strategies** (`ExactMatch`, `SplitCoin`, `UnloadIntoCoins`) to declare their assets
   through the builder, then `register(inputs:outputs:)` from `assets`. Behavior-neutral in this phase.

### Phase 3 — Two-phase handoff

1. **`DurabilityStoring`**: add `markHandoffPending([OwnAsset])`, `commitHandoffs([OwnAsset])`,
   `releaseUncommittedHandoffs()`. Map to `CoinHandoffMark.pending` / `.committed` / clear-pending
   (no schema change — `handoffMark` Int16 already encodes them).
2. **`DurabilityService`**: `preCommitHandoff([OwnAsset]) -> CoinageHandoffCommit`,
   `releaseUncommittedHandoffs()`. Keep the invariant check (a `.pending`/`.committed` asset can't be
   a live input) at the store layer.
3. **`CoinageHandoffCommit.swift`** (NEW): protocol `{ func commit() async throws }` + impl capturing
   the asset keys and the store.
4. **`TransferSenderService.execute`**: split into foreground `prepare` (mint via builder → register →
   `insertOutputs` → `preCommitHandoff` → build memo) returning `(memo, handoffCommit)`, and the
   existing background `submitRegistered` + `settle`. Move recipient-coin handoff to **pre-submit**
   (fixes the current post-success window in `SplitCoinStrategy`).
5. **`CoinageServicing.executeTransfer`**: return `PreparedTransfer(memo, handoffCommit)` instead of
   bare `TransferMemo`.
6. **Transports call `commit()` inside their durable write:**
   - `TransferAmountInteractor`: hold the handle, `commit()` after `sendTransfer` durably persists.
   - `LocalMessageCreatingOperationFactory` (chat): `commit()` in the local-message-row op.
   - `W3sStatementSubmitter`: `commit()` in the `W3sPaymentRecord` write.
7. **App launch**: `ServiceCoordinator+Coinage` calls `releaseUncommittedHandoffs()` once on startup.

## North-Star Alignment

Converges iOS onto the same "local row ⋈ ledger claim" model Android already runs: one derive-on-read
overlay at selection, an explicit transaction builder, and a two-phase handoff that makes the
double-spend-vs-frozen-coins invariant hold across process death. Reduces cross-platform divergence in
the security-sensitive send path.

## Risks

- **Handle plumbing across transports.** `executeTransfer` return-type change ripples into chat / W3SPay /
  TransferAmount. Mitigation: introduce `PreparedTransfer` and migrate callers one transport at a time;
  a not-yet-committed handle is safe (released on relaunch).
- **Ordering regressions in `execute` split.** prepare/submit boundary must keep register-before-submit
  and preCommit-before-memo-leaves. Mitigation: keep the background submit path byte-identical to today;
  only hoist mint/register/preCommit/memo ahead of it.
- **Products payment path may bypass `executeTransfer`.** Audit `ProductsNativeApi+Payment`; if it builds
  a memo directly it either needs a handle too or is explicitly out of scope.
- **Durability store change touches persistence.** Confined to additive store methods over the existing
  `handoffMark` column; no model version bump.

## Verification

- [ ] Phase 0: `xcodebuild ... build` green (module compiles; deferred errors gone).
- [ ] Phase 2: strategies build assets via the builder; balance/selection behavior unchanged.
- [ ] Phase 3: uncommitted handoff released on relaunch; committed one survives (mirror Android
      `DurabilityHarnessSmokeTest`).
- [ ] Recipient coins marked `.pending` before the memo can leave (no unmarked-key window).
- [ ] Each transport commits inside its durable write; a failed send leaves coins spendable after relaunch.
- [ ] Build succeeds; targeted tests pass.
