# Host-api worker integration — plan, decisions, open questions

Status doc for the "workers ref counter + host-api storage-subscribe + operations" task.
Written to be checked while the author is away. Updated as chunks land.

## What the task asks

1. Workers get a ref counter. Start on first consumer, dispose when the last leaves.
   Simple native Swift API shaped like `lock` / `unlock`. Ref count rises on the chats
   screen and when the product's full-page screen (codename "funcing"/"getcash") opens.
2. Link the local `triangle-js-sdks` packages and integrate, on the worker (JS) side,
   only: local storage subscribe, and operations begin/end.
3. Begin operation raises the worker ref count and persists the operation on the host
   (CoreData). End operation is idempotent and lowers the ref count.

## Codename decoding (verified against the repo)

- "funcing"/"getcash" are not literal identifiers anywhere. They map to the **product**
  subsystem. A product's full-page app is the **SPA** VIPER module (`Modules/SPA/`).
- A **worker** is a product's background JS runtime. Today it is owned one-per-`ProductBot`
  (chat extension), created by `ProductBotFactory`, started in
  `ProductBot.deliverAutomaticMessages`, disposed by `ProductBot.dispose`/`deinit`.
  Protocol: `ChatRuntimeProtocol` (`Modules/Products/ProductRuntimeProtocol.swift`).
- The SPA app runtime is a **separate** JS surface from the worker; today the SPA screen
  does not touch the worker.

## How the JS ↔ native bridge works (verified)

- The iOS app bundles the JS host container from `Packages/Products/product-container/`
  (esbuild → `dist/container.js`), a copy of which is served from
  `Packages/Products/Sources/Products/Resources/container.js`.
- `product-container/src/index.ts` wires `@novasamatech/host-container`'s `Container`
  handlers to `callNative(...)` / `subscribeNative(...)`, which post JSON messages to the
  Swift `ContainerBridge` (`webkit.messageHandlers.__container__`).
- Swift `ContainerBridge+HostApi.swift` registers camelCase JSON handlers
  (`registerRequestHandler` / `registerSubscriptionHandler`) that call
  `ProductsNativeApiProtocol`.
- host-api transport method names (SCALE) are e.g. `host_local_storage_subscribe`,
  `host_worker_begin_operation`, `host_worker_end_operation`. The camelCase JSON names
  crossing to Swift are chosen by `product-container` (`localStorageSubscribe`,
  `workerBeginOperation`, `workerEndOperation` used here, matching existing convention).

## host-api protocol shapes being integrated (from triangle-js-sdks @ 0.9.4)

- `protocol/v1/localStorage.ts`
  - `StorageSubscribeV1_start = { key }`, `_receive = { value: Option(Bytes) }`, `_interrupt = void`.
  - Contract: **emit the current value first**, then one item per later write/clear.
    `None` == cleared/absent. The native side must synthesise the initial value.
- `protocol/v1/worker.ts`
  - `OperationId = u32` (host-assigned, unique per product).
  - `WorkerBeginOperationV1_request = { label: Option(str) }` → `CallResult({ id }, WorkerErr)`.
  - `WorkerEndOperationV1_request = { id }` → `CallResult(void, WorkerErr)`, **idempotent**.
  - `WorkerErr = { TooManyOpen, Unknown }`.
  - Comment: "the host keeps the product's worker running while it has at least one open
    operation" → begin = lock, end = unlock.

## Chunk plan (each builds and is reviewed before the next)

1. JS: link local `@novasamatech/*`, add the three `Container` handlers in
   `product-container/src/index.ts`, rebuild `container.js`, copy into `Resources/`.
   Verify: esbuild succeeds, the three method names appear in the bundle.
2. Native bindings: add `subscribeLocalStorage`, `workerBeginOperation`,
   `workerEndOperation` to `ProductsNativeApiProtocol` + `ContainerBridge` handlers.
   Storage subscribe emits the current value first. Verify: Swift build.
3. `ProductWorkerManager` — the lock/unlock ref counter. Start on 0→1, dispose on →0.
   Thread-safe (`OSAllocatedUnfairLock`, matching `TrUAPIChainConnectionPool`). Verify:
   unit test with a fake runtime factory.
4. Operations persistence + wiring. CoreData entity for open operations; begin persists a
   row + locks + returns id; end removes the row + unlocks (idempotent). Verify: unit test.
5. Lockers. SPA interactor locks on setup / unlocks on teardown. Chat locks per active
   product. See the open question on chat below.

## Key design decisions

- Ref-count API is a token: `lock(productId:) -> ProductWorkerToken`; the token releases
  once, on explicit `unlock()` or on `deinit` (leak safety). This still reads as lock/unlock
  and stops a forgotten unlock from pinning a worker forever. Operations map
  `operationId -> token` so `end` releases the right one.
- The manager builds the worker runtime through an injected factory so it is testable
  without the real WKWebView/JS.

## Open questions (need the author)

- OQ1 (chat unification): RESOLVED. Option a shipped. Chat no longer owns a worker. The
  native chat runtime is `ManagedChatRuntime`, which locks the shared manager, drives the one
  booted worker, and binds chat messaging only while the chat surface is alive. SPA,
  operations and chat now all ref-count a single per-product instance. The one thing CI cannot
  cover is the live JS chat round-trip (onBotStarted / onUserMessage / chatSendTextMessage on
  the shared engine); it needs a device smoke test. See the chunk-6 note.
- OQ2: RESOLVED. Worker headless start is wired. `DefaultProductWorkerFactory` boots the
  worker with a nil `MessagingSupport`; a product opened only via its SPA screen runs the
  worker with no bot and no `onBotStarted`, and chat binds messaging later if it attaches.
- OQ3: `TooManyOpen` cap. host-api allows rejecting `begin` with `WorkerErr.TooManyOpen`.
  Is there a desired per-product open-operation limit? Default: no cap for now.
- OQ4: operation persistence lifetime. On app relaunch, orphaned persisted operations from a
  previous run would pin workers forever. Default: clear all persisted operations on app
  start (a process-lifetime keep-alive record, persisted only so an interface can list them
  later per the task). Confirm this is the intended semantics.
- OQ5: rust runtime backend (`.truApiRuntimeEnabled`). This work targets the native
  (WKWebView) backend. The rust backend path (`ChatRustRuntime`, `SPARustRuntimeInteractor`)
  is left untouched, so the SPA worker lock is only wired on the native path. Confirm that is
  fine, or the same lock needs adding to the rust SPA interactor.
- OQ7: operation persistence store. It is a JSON file in the shared container behind
  `ProductOperationStoring`, not the CoreData `UserDataModel`. A blind additive migration on
  the shared v42 store (loaded with `incompatibleModelStrategy: .ignore`) has app-launch /
  data-loss blast radius and cannot be verified without a device migration test. Swap to a
  `CDProductOperation` entity behind the same protocol once the listing UI lands and the
  migration can be verified: new `UserDataModel43.xcdatamodel` (attributes only → automatic
  lightweight migration), a `UserStorageVersion.version43` case + `nextVersion` transition,
  bump `UserStorageParams.modelVersion`, add a `CoreDataCodable` mapper + repository.

## Progress log

### Chunk 1 — JS side (DONE)
- Added three `Container` handlers in `product-container/src/index.ts`:
  `handleLocalStorageSubscribe`, `handleWorkerBeginOperation`, `handleWorkerEndOperation`
  (native JSON method names `localStorageSubscribe`, `workerBeginOperation`,
  `workerEndOperation`). Imported `WorkerErr`.
- Linked the local `triangle-js-sdks` 0.9.4 packages into `product-container/node_modules`
  via symlinks (node_modules is gitignored). Bumped `product-container/package.json` deps
  0.9.0 → 0.9.4 so a real install reproduces the bundle.
- Rebuilt with esbuild → `dist/container.js`, copied into the tracked
  `Sources/Products/Resources/container.js`. All three `host_*` transport method names are
  present in the bundle.
- Finding: the `container.js` diff is large (~1100 lines) because the whole SDK bumped
  0.9.0 → 0.9.4, not just the two features (the two methods only exist in 0.9.4). This
  matches the task title "integrate latest changes from host-api". OQ6 below covers the
  risk that other 0.9.x protocol changes affect existing native handlers.
- Finding: `tsc --noEmit` on `product-container` reports 48 errors, but they are a single
  systemic `Promise<Result>` vs `ResultAsync` mismatch hitting every async handler
  identically (neverthrow type tightened between 0.9.0 and 0.9.4). My new subscription
  handler is clean; my two request handlers match the exact shape of the existing
  production handlers. esbuild ignores types and bundles correctly; runtime contract is
  unchanged. Not fixing the pre-existing drift here.
- OQ6: bumping the bundle to 0.9.4 pulls every 0.9.1–0.9.4 protocol change into the app,
  not only the two scoped features. A full protocol-delta audit against the existing native
  handlers was not done. Confirm the SDK bump is intended (the task title implies yes) and
  that a QA pass on existing product features is planned.

### Chunk 2 — native local storage subscribe (DONE, builds clean)
- `ProductLocalStorageProtocol.subscribe(key:)` added (package). `ProductsLocalStorage`
  (app) implements it with a lock-guarded per-key `AsyncStream` set: emits the current
  value under the lock (so a concurrent write cannot jump ahead of it), then on every later
  write/clear. Stored values are opaque hex (JS does `toHex`/`fromHex`), so subscribe emits
  the same stored string `read` returns.
- `ProductsNativeApiProtocol.subscribeLocalStorage(key:)` + `ContainerBridge`
  `registerLocalStorageSubscribe` (method `localStorageSubscribe`) map it to
  `{ value: string | null }`.
- The single conformer to the storage protocol is `ProductsLocalStorage`; `TrUAPILocalStorage`
  uses a different protocol, so nothing else broke.
- Confirmed compiling: the chunk-2 background app build exited 0.

### Chunk 3 — worker ref counter (DONE, unit-tested)
- `ProductWorkerManager` in `Modules/Products/Worker/`. API is a token: `lock(productId:)
  -> ProductWorkerToken`; the token releases once, on `unlock()` or deinit (leak-safe).
- Ref-counted per product. A serialized per-entry lifecycle chain guarantees a single
  worker at a time and correct start-before-dispose ordering under rapid lock/unlock.
- The boot is an injected `ProductWorkerFactory?` seam. Optional: with no factory,
  lock/unlock still ref-counts and operations still persist; it just starts no JS worker
  (see OQ1/OQ2).
- Tests: `ProductWorkerManagerTests` — starts once for concurrent consumers, disposes only
  on the last unlock, idempotent token unlock, deinit release, and a rapid-toggle
  convergence test (no leaked worker).

### Chunk 4 — operations: persistence + native bindings (DONE, unit-tested)
- `ProductsNativeApiProtocol.workerBeginOperation(label:)` / `workerEndOperation(id:)` +
  `ContainerBridge` handlers (methods `workerBeginOperation` → `{ id }`, `workerEndOperation`).
- `ProductWorkerOperationService` (`ProductWorkerOperating`): begin assigns a random u32 id
  (nonzero, unique among the product's open operations), locks the worker (holds the token),
  persists a record, returns the id; end unlocks +
  deletes, idempotent for unknown/already-ended ids. A persistence failure on begin rolls the
  lock back.
- Persistence behind `ProductOperationStoring`; concrete `FileProductOperationStore` (JSON in
  the shared container, actor-serialized, atomic writes). Cleared on launch
  (`resetForNewSession`) — process-lifetime keep-alive (OQ4). CoreData entity deferred (OQ7).
- Shared composition: `ProductWorkerServices.shared` owns the manager + operation service and
  is injected into `ProductsNativeApiFactory` at both build sites (chat `ProductBotFactory`,
  `SPAViewFactory`).
- Tests: `ProductWorkerOperationServiceTests`.

### Chunk 5 — lockers (DONE, native backend)
- SPA screen: `SPANativeRuntimeInteractor` holds a `ProductWorkerToken` for the product,
  acquired in `SPAViewFactory` and released on the interactor's deinit. So opening a
  product's full-page screen raises the worker ref count and closing it lowers it.
- Chat screen: wired via chunk 6. The native chat runtime now locks the manager instead of
  booting its own worker, so a bot on the chats screen raises the same ref count.

### Chunk 6 — chat unification (DONE, builds + unit-tested; needs a device smoke test)
- Worker boot factory `DefaultProductWorkerFactory` now boots the real headless worker: it
  resolves the product's worker source by id, builds the executor and a headless
  `ProductsNativeApi`, calls `initializeBot`, and returns a `ProductScriptWorker`. Installed
  once at launch via `ProductWorkerServices.configure(factory:)` from
  `ServiceCoordinator+ChatExtension`, where the product dependency graph already exists.
- `ProductScriptWorker` (`ProductChatWorking`) is the one worker instance the manager owns:
  it wraps the executor plus its native API and exposes the chat-driving surface
  (onBotStarted / onUserMessage / renderMessage / dispatchEvent / attach) and messaging
  bind/unbind. Non-chat consumers only keep it alive through `ProductWorkerRunning.dispose`.
- `ProductWorkerManager.acquire(productId:)` locks, waits for the boot, and hands back the
  running worker so chat can drive it; keep-alive consumers still use `lock`.
- `ManagedChatRuntime` replaces `ChatNativeRuntime` on the native path. It single-flights one
  lease, binds messaging on `start` (before `onBotStarted`, so a welcome message still
  routes), forwards chat calls to the shared worker, and on `dispose` unbinds messaging and
  releases the lock. Chat is now just another ref-count consumer: the worker boots once for
  whoever needs it first and is torn down when the last of chat / SPA / operations releases.
- Messaging binding is a mutable, lock-guarded seam on `ProductsNativeApi`
  (`bindMessaging` / `unbindMessaging`, read once via `currentMessaging`). The bot stays weak,
  so the worker never pins the `ProductBot`; `context` is cleared on unbind.
- `ProductBotFactory` native path shrank to `ManagedChatRuntime(productId:manager:)`; the
  executor/native-API assembly moved wholesale into `DefaultProductWorkerFactory`. The rust
  path is unchanged (native-only unification; rust ref-counting is still OQ5).
- Tests: `ChatRuntimeTests` native cases rewritten to drive `ManagedChatRuntime` against a
  fake manager + worker (bind + start, forward, dispose unbinds and releases). Rust cases
  untouched. `ProductWorkerManagerTests` / `ProductWorkerOperationServiceTests` still green.
- Device smoke test still owed: open a product's chat, confirm the welcome message and a
  user-message reply still flow, then open its SPA screen and confirm the worker stays a
  single instance (one boot, torn down only after both close).

## What is wired vs pending

Wired and verifiable now (build + unit tests): the JS handlers, native storage subscribe,
the ref-count manager, the operations service with persistence, the native operation
bindings, the shared composition, and the SPA ref-count locker.

Pending, needs a product decision and device verification: the concrete worker-boot factory
(OQ2) and the chat locker + chat/worker unification (OQ1). Until those land, `lock`/`unlock`
and operations ref-count and persist correctly, but no JS worker actually boots from the
manager — the chat `ProductBot` remains the only thing that boots a worker, exactly as
before this change.

## Recommended follow-up (the unification, for when it can run on a device)

1. Add a headless start to the worker runtime: split `ChatRuntimeProtocol.start` so the JS
   worker can boot and register host-api handlers without chat `MessagingSupport` and without
   `onBotStarted`; let chat attach messaging afterwards.
2. Implement `DefaultProductWorkerFactory`: resolve the product (`ProductResolving` +
   dot-ns), build the worker runtime via `ProductBotFactory`'s native path, start it headless,
   return it as a `ProductWorkerRunning`. Inject it into `ProductWorkerServices` (break the
   factory→service→manager→factory cycle by setting the factory on the manager after the
   service is built).
3. Make chat source its worker from the manager: `ProductBotProvider`/`ChatExtensionStore`
   lock the manager per active product and wrap the shared runtime in a `ProductBot`, instead
   of `ProductBotFactory` building a private runtime. Unlock on removal.
4. Then a single worker per product is shared by chat, SPA, and operations, and dispose-on-
   zero is real end to end.

## Build-environment notes (things I hit)

- SwiftFormat build phase: the app target has a "Run Swiftformat" build phase
  (`alwaysOutOfDate = 1`) that rewrites the whole repo on every build. In a clean checkout
  a build modifies ~75 unrelated files (formatting only, e.g. expanding `if x { return }`).
  Those are not part of this change; I reverted them. Expect them to reappear on any build.
- Tests need a Firebase secret: the `Google info` build phase does `exit 1` when
  `polkadot-app/GoogleService/GoogleService-Info-Dev.plist` is missing, which cancels the
  test build. Secrets were stripped from this checkout, so only the `.template` is present.
  To run the tests I copied the template to the real (gitignored) filename locally. That is a
  placeholder Firebase config, not a real one; it is not committed.

## Code review (self + independent pass)

Two fixes applied after review:
- `endOperation` was not idempotent across a persistence failure: it unlocked the token, then
  a failing `store.delete` propagated an error, so a retry no-oped (token already gone) and the
  row orphaned. Fixed by always releasing the worker and making the delete best-effort
  (logged, never throws) so `end` always succeeds and never pins the worker — matching the
  host-api "end is idempotent and always succeeds" contract. Regression test added.
- `ProductsLocalStorage.write`/`clear` mutated storage outside the lock and notified inside it,
  so a `subscribe` racing a write could emit the new value twice, and two concurrent writes to
  the same key could deliver out of order. Fixed by making mutate+notify a single critical
  section.

Verified sound by the independent pass: the `ProductWorkerManager` start/dispose ordering
under rapid lock/unlock (no leak, no double start/dispose), `ProductWorkerToken` exactly-once
release, the service↔manager lock ordering (no deadlock), `beginOperation` rollback, and the
bridge JSON shapes.

## Verification reality

Verified here:
- esbuild bundle + bundle grep, all three `host_*` methods present (chunk 1).
- The app + Products package + test target all compile (chunks 2-5), iPhone 16e simulator.
- `ProductWorkerManagerTests` + `ProductWorkerOperationServiceTests`: 8 tests in 2 suites,
  all passed (`** TEST SUCCEEDED **`). To run them I had to erase a corrupted simulator,
  create the placeholder Firebase plist above, disable parallel testing (`-parallel-testing-
  enabled NO` against a booted sim by id), and remove `product-container/node_modules` — its
  build-time symlinks are bundled into the app and break install as invalid symlinks. Do the
  npm link in a throwaway location, or delete `node_modules` before building the app.

Not verified here (no device / live product JS): chat still works, SPA keeps the worker
alive, a product calling `beginOperation` survives backgrounding, storage subscribe delivers
to a real worker. These depend on the pending worker-boot + chat integration (OQ1/OQ2).
