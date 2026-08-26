---
task: Coinage durability — relational CoreData model + derive-on-read status + subscription propagation
date: 2026-08-25
status: draft
files_touched:
  # CoreData model (edited in place — NO version bump)
  - polkadot-app/Common/Storage/UserDataModel.xcdatamodeld/UserDataModel43.xcdatamodel/contents
  # Durability persistence (app target — Modules/Coinage/Model/CoreData)
  - polkadot-app/Modules/Coinage/Model/CoreData/DurabilityEntryMapper.swift
  - polkadot-app/Modules/Coinage/Model/CoreData/HandoffMarkMapper.swift
  - polkadot-app/Modules/Coinage/Model/CoreData/DurabilityCoreDataStore.swift
  - polkadot-app/Modules/Coinage/Model/CoreData/CoinageTransactionContext.swift
  # Coin/Voucher mappers + providers (app target — Modules/TransferAmount/Model/CoreData)
  - polkadot-app/Modules/TransferAmount/Model/CoreData/CoinMapper.swift
  - polkadot-app/Modules/TransferAmount/Model/CoreData/CoinStateMapper.swift          # DELETE
  - polkadot-app/Modules/TransferAmount/Model/CoreData/VoucherMapper.swift
  - polkadot-app/Modules/TransferAmount/Model/CoreData/VoucherLocationMapper.swift
  - polkadot-app/Modules/TransferAmount/Model/CoreData/CoinageDatabaseDependencyFactory.swift
  # Coinage package — models
  - Packages/Coinage/Sources/Models/Coin.swift
  - Packages/Coinage/Sources/Models/Voucher.swift
  - Packages/Coinage/Sources/Durability/Model/DurabilityEntry.swift
  - Packages/Coinage/Sources/Durability/Model/AssetRef.swift
  # Coinage package — store interfaces
  - Packages/Coinage/Sources/Durability/Store/DurabilityStoring.swift
  - Packages/Coinage/Sources/Durability/Store/CoinageTransacting.swift
  # Coinage package — remove push-projection, add derivation
  - Packages/Coinage/Sources/Durability/Engine/ProjectionReconciler.swift            # DELETE
  - Packages/Coinage/Sources/CoinService.swift                                       # remove apply(state:)
  - Packages/Coinage/Sources/VoucherService.swift                                    # remove mark*/delete
  - Packages/Coinage/Sources/CoinStateSyncService.swift                              # DELETE (confirm exact path)
  - Packages/Coinage/Sources/CoinageService+make.swift                               # rewire DI
  - Packages/Coinage/Sources/Durability/Derivation/AssetStatusDeriver.swift          # NEW
  - Packages/Coinage/Sources/Durability/Derivation/BalanceClassifier.swift           # NEW
  # Tests
  - polkadot-appTests/Common/CoreData/CoreDataMapperTests+CoinMapper.swift
  - polkadot-appTests/Common/CoreData/CoreDataMapperTests+VoucherMapper.swift
  - polkadot-appTests/Common/CoreData/CoreDataMapperTests+VoucherLocationMapper.swift
  - polkadot-appTests/Common/CoreData/CoreDataMapperTests+CoinStateMapper.swift       # DELETE
  - polkadot-appTests/Coinage/DurabilityRegistrationConcurrencyTests.swift
  - polkadot-appTests/Coinage/CoinVoucherSubscriptionTests.swift                      # NEW
  - Packages/Coinage/Tests/Durability/AssetStatusDerivationTests.swift                # NEW
  - Packages/Coinage/Tests/Durability/ (existing suites adapted to relational store)
seams_used:
  - CoreData models (*.xcdatamodeld) — entity/attribute changes
  - User storage facade — UserDataStorageFacade (no version enum change: edited in place)
  - Separate mappers for partial updates (CoinStateMapper pattern retired; VoucherLocationMapper trimmed)
  - willChange/didChange TouchParent pattern (CDChatRequest+TouchParent) for subscription propagation
  - Coin models / Transfer planning seams (Packages/Coinage)
must_not_touch:
  - Any other UserDataModel version dir (41, 42) — only 43 is edited
  - SubstrateDataModel.xcdatamodeld
  - Non-coinage entities in UserDataModel43 (chat, contacts, game, etc.)
  - UserStorageVersion / UserStorageParams.modelVersion (stays .version43)
out_of_scope:
  - gap-limit rescan / recovery on reinstall (spec: out of scope)
  - coin selection policy, locked-coin / recycler-onboarding eligibility (outer layer)
  - UI/screen redesign — readers keep reading domain Coin.state / Voucher.localState
  - New xcstrings / localization
---

## Goal

Move coin/voucher *local* status out of stored CoreData fields into a relational durability
graph, compute status **on read** from that graph (retiring the push-projection), and make
coin/voucher subscriptions refire when a related durability entry changes — via the
`willChange`/`didChange` TouchParent pattern.

## Approach

The durability spec defines an asset's local status as a pure function of its entry DAG
(statuses of the entries that consume/mint it) plus its handoff mark. Today (v43) that status
is **pushed**: `ProjectionReconciler` recomputes and writes `CDCoin.state` / `CDVoucher.localState`
after every change. We invert to **pull**: model the graph with real relations
(`CDDurabilityInput`/`CDDurabilityOutput` linking to `CDCoin`/`CDVoucher`), delete the stored
status columns and the reconciler, and derive status **at mapper/provider fetch time** so the
existing 13 reader sites keep reading `Coin.state` / `Voucher.localState` unchanged.

**Locked decisions (from clarification + Lavish review):**
1. **Scope = full target solution** — derive on read; remove `ProjectionReconciler` (Option B).
2. **Edit `UserDataModel43` in place** — no version bump, no migration; dev stores are disposable.
3. **Field types follow the task literally** — hex `String?` hashes, `NSNumber?` block numbers, `groupId String?`.
4. **`sequence Int64` is the identity** — drop the UUID `identifier`; `TransactionId = sequence`.
5. **Tests** — integration over `UserDataStorageTestFacade` + derivation unit tests.

## Steps

### 1. Edit UserDataModel43 in place
- Modify `UserDataModel43.xcdatamodel/contents` directly. Do **not** add a version or touch
  `UserStorageVersion` / `nextVersion()` / `UserStorageParams.modelVersion`.
- Caveat: same version name + changed schema ⇒ existing dev store is incompatible and will not
  lightweight-migrate. Verify the facade resets the store on load failure (or wipe dev data).

### 2. Redefine coinage entities in v43
- **CDCoin**: keep `identifier · age · derivationIndex · exponent`. Remove `state`. Add inverse
  rels: `inputs` (to-many ↔ CDDurabilityInput.coin), `mintedBy` (to-one ↔ CDDurabilityOutput.coin),
  `handoffMark` (to-one ↔ CDHandoffMark.coin).
- **CDVoucher**: keep `identifier · allocatedAt · derivationIndex · exponent · privacy · readyAt ·
  recyclerIndex`. Rename `state` → `remoteState`. Remove `localState`. Add inverse rels `inputs`
  (to-many), `mintedBy` (to-one). Deletion rule so a voucher is never cascade-deleted.
- **CDDurability** (rename `CDDurabilityEntry`): `sequence Int64` (unique identity), `groupId String?`,
  `txHash String?` (hex), `status Int16`, `createdAt Date`, `mortality Int64`, `checkpointHash String?`,
  `checkpointNumber NSNumber?`, `successHash String?`, `successNumber NSNumber?`. Rels `inputs`
  (cascade ↔ CDDurabilityInput), `outputs` (cascade ↔ CDDurabilityOutput). Drop UUID `identifier`.
- **CDDurabilityInput** (new): `receivedPubKey String?`; rels `coin?`, `voucher?`, `entry`.
- **CDDurabilityOutput** (new): rels only — `coin?`, `voucher?`, `entry`.
- **CDHandoffMark**: keep `identifier · createdAt`; add `state Int16` (0 precommit / 1 commit) and
  rel `coin?`. Insert-only, never retracted.
- **Delete CDEntryAsset**.
- Relationship cardinality: `coin.inputs` / `voucher.inputs` are **to-many** (a FAILURE entry
  releases its claim, so the same asset can be an input of one failed + one live entry). `mintedBy`
  and `handoffMark` are to-one (Fresh-outputs invariant / one mark per coin).
- Deletion rules: nullify on the coin/voucher side; cascade only `CDDurability → inputs/outputs`.

### 3. Rewrite the durability + coin/voucher mappers
- **DurabilityEntryMapper**: map `DurabilityEntry` ↔ `CDDurability`. Resolve `CDCoin`/`CDVoucher`
  by `derivationIndex` and link Input/Output rows; a `Received` input stores `receivedPubKey`
  (hex) with no coin/voucher rel. Encode hashes as hex `String`, numbers as `NSNumber`; carry
  `groupId`. Reconstruct `inputs`/`outputs` from the typed relations (no more `"coin:N"` strings).
- **HandoffMarkMapper** + the `HandoffMark` domain struct: add `state` and the coin link.
- **CoinMapper**: stop reading/writing `state`. **VoucherMapper**: `state` → `remoteState`, drop
  `localState`. **Delete CoinStateMapper**. Trim `VoucherLocationMapper` to `remoteState` / privacy /
  recyclerIndex (drop `localState` writes).

### 4. Rewire the registration-atomicity queries
- `CoinageTransactionContext` / `CoinageStoreTransaction` enforce Unique-consumer, Blocked-handoff,
  Fresh-outputs via `CDEntryAsset` identifier predicates. Re-express against the new relations:
  predicates over `CDDurabilityInput.coin.derivationIndex` / `.voucher.derivationIndex` /
  `receivedPubKey`, `CDDurabilityOutput.coin/voucher`, and `CDHandoffMark.coin`. Behaviour
  preserved; only the storage shape changes. `nextSequence()` stays and feeds the identity.
- Update `DurabilityStoring` / `CoinageTransacting` where `TransactionId` was the UUID — it is now
  the `sequence`, assigned at registration and returned from `submitTransaction`.

### 5. Subscription propagation
- Add `CDDurability+TouchAssets.swift`: after a status write, `willChangeValue`/`didChangeValue`
  on each related `CDCoin`/`CDVoucher` (via `#keyPath(CDCoin.inputs)` etc.), mirroring
  `CDChatRequest+TouchParent`. `CDHandoffMark` touches its `coin` on insert.
- Call the touch after `populate()` in `CoinageTransactionContext.upsert(_:)` and `insertMark(_:)`.

### 6. Remove push-projection; derive status on read
- **Delete** `ProjectionReconciler`, `CoinStateSyncService`, `CoinStateMapper`,
  `CoinService.apply(state:)`, `VoucherService.mark*` / `delete`.
- Add pure derivation functions over the new relations (spec §Derived state / §Derived views):
  `AssetStatus` (Idle/InUse/HandedOff), `reserved`/`available`/`selectable`/`spent`, Balance
  classification (1–4), Appendix A payment status.
- Populate `Coin.state` / `Voucher.localState` from these **at fetch time** in the mapper/provider
  by joining the asset's `inputs`/`outputs`/`handoffMark`, so the 13 readers stay unchanged.
  Thread the durability engine's pinned `F`/`B` where a view needs the chain head.
- Update `CoinageService+make.swift` DI to drop the reconciler/sync wiring.

### 7. Tests
- **Integration** (`UserDataStorageTestFacade`, Swift Testing): coin/voucher `subscribeSnapshot`
  re-emits when a related entry's `status` changes and when a handoff mark is inserted; no emit for
  unrelated rows; mapper round-trips (relational inputs/outputs, received key, hex hashes,
  `NSNumber`, handoff state).
- **Unit**: `AssetStatusDeriver` / balance classification — entry statuses + handoff mark →
  status, covering terminal-vs-live, handed-off, and reserved cases.
- Adapt `DurabilityRegistrationConcurrencyTests` and the `Packages/Coinage/Tests/Durability` suites
  to the relational store. Delete `CoreDataMapperTests+CoinStateMapper`.

## North-Star Alignment

Replaces stored, push-reconciled derived state with a normalized relational graph and pull-based
derivation — a single source of truth (the entry DAG) with status computed from it, matching the
durability spec. Removes the reconciler as a class of drift bug and uses the established
TouchParent idiom for change propagation.

## Risks

- **R1 (resolved)** — keep `sequence` as identity; drop UUID `id`; `TransactionId = sequence`.
- **R2 (resolved)** — Option B: derive on read now, delete `ProjectionReconciler`; no inert-status window.
- **R3** — received-key uniqueness enforced via predicate over `receivedPubKey` + entry status (Step 4).
- **R4** — hex `String` / `NSNumber` less efficient than Binary/scalar; accepted (follows the task).
- **R5** — coins/vouchers must not cascade-delete graph rows; nullify their side, cascade only entry→in/out; remove `VoucherService.delete()`.
- **In-place v43 edit** — dev store incompatibility; rely on store reset / wipe.

## Verification

- [ ] App loads UserDataModel43 with the new schema (store resets cleanly on incompatibility).
- [ ] Round-trip: entry with own-coin + received + voucher inputs and coin outputs reconstructs identically.
- [ ] Subscribed coin re-emits on its entry's status change and on handoff insert; unrelated coin does not.
- [ ] `DurabilityRegistrationConcurrencyTests` pass against relation-based queries.
- [ ] Derivation unit tests cover terminal/live/handed-off/reserved.
- [ ] Build succeeds (app + Coinage package).
- [ ] `polkadot-appTests` + Coinage tests pass.
