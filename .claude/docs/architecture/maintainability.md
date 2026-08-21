# Maintainability Principles

Cross-cutting guidelines that apply to all code in the project. These are derived from recurring PR review feedback and team conventions.

## Docs Travel With Code

PRs that introduce new behavior, conventions, or architectural decisions must extend or update these docs in the same PR. The doc change is part of the diff, not a follow-up:

- New rule or anti-pattern surfaced in review → add it to the relevant `.claude/docs/**` file (and a checklist item under `review/`).
- New package, module pattern, or migration target → update `architecture/multi-package.md` / `architecture/viper.md` / the relevant architecture doc, plus a line under `Recently Changed` in `docs/README.md`.
- Removal of a subsystem (e.g., a service, vendor SDK, or build flag) → scrub every mention across `.claude/docs/**` and `CLAUDE.md` in the same PR.
- A reviewer should never have to ask "where do we document this now?" — the answer is in the same diff.
- RFC-driven changes fold into the existing sections describing the resulting behavior — never add a per-RFC section. Docs are organized by subsystem behavior; RFC numbers may appear only as inline citations for a specific normative rule. The same applies to code comments: describe the mechanism itself, cite an RFC only when a specific requirement comes from it (e.g. a consent rule or wire formula).

If you don't know where it belongs, default to `architecture/maintainability.md` and link from the more specific doc.

## Core Principles

### 1. Reuse Before Build

Before writing new code, check if the capability already exists:
- `SubstrateSdk` / `SubstrateSdkExt` for blockchain utilities
- `StructuredConcurrency` for async helpers (`withRetry`, bridging, debounce)
- `AsyncExtensions` for async stream utilities (`AsyncPassthroughSubject`)
- `FoundationExt` / `UIKitExt` for common extensions
- `PolkadotUI` for UI components
- `Common/` for shared app-level utilities
- Existing HTTP constants (`HttpMethod.post`, `HttpContentType`, `HttpHeaderKey`)
- `UserNotificationServicing` instead of direct `UNUserNotificationCenter`
- `UsernameStorage` for local username access (don't query chain for own username)
- `StorageRequestFactory.asyncInit()` for async blockchain storage requests
- `requestFactory.queryByPrefix` instead of `keysFactory.createKeysFetchWrapper`
- `getChainAsset` from chain registry instead of manual chain+asset construction

This is the **#1 most common review feedback**: "we already have X, use it."

### 2. Single Responsibility

Each class/service/module has one job:
- Do not inject unrelated concerns into existing services
- Post state changes and let consumers interpret them
- Feature boundaries are real — keep module internals private

### 3. Throw Errors, Don't Fallback Silently

- Prefer to declare and throw an error instead of force unwrapping optionals
- Never silently degrade to raw data or default values
- If expectations are not met, fail explicitly

### 4. Clean Up Dead Code

- Remove unused methods, properties, and files
- Replace unreachable values with computed functions
- Remove debug leftovers before merging

### 5. Extract Reusable Logic to Packages

When logic will be reused:
- Conversion utilities → appropriate package extension (e.g., `SubstrateSdkExt`)
- Shared business logic → domain-specific package
- UI components → `PolkadotUI`
- Shared wireframe presentation logic → wireframe extension for reuse between modules

When logic is used by only ONE consumer, keep it as a `private extension` co-located with that consumer.

#### Where does it belong? (SubstrateSdkExt vs feature package vs app)

The line is between **Substrate primitives the SDK already names** and **our domain models built on top**:

| Knows about...                                                     | Goes to                              |
|--------------------------------------------------------------------|--------------------------------------|
| `AccountId`, hex, SCALE, runtime metadata, generic chain prefix    | `SubstrateSdkExt`                    |
| `ChainModel`, `AssetModel`, `RuntimeProvider`, connection pool     | `ChainRegistry` (feature package)    |
| `BackupStatus`, `SelectedUsername`, app-only state                 | `polkadot-app/Common/` or feature module |
| Secrets, API keys, environment-specific values                     | App, injected via provider protocol  |

This was codified when `SubstrateSdkExt` was extracted: `AddressConversion`, `RawDataStorageSubscription`, `StorageSubscriptionContainer`, `CallMetadata+TypeCheck`, `CodingFactory+TypeCheck`, `RuntimeMetadata+Internal` all knew only Substrate primitives and were moved out of `ChainRegistry` into `SubstrateSdkExt`. `ConnectionApiKeys` knew app secrets and was moved the other way — out of the package into `polkadot-app/Common/ChainRegistry/ConnectionApiKeysProvider.swift`, injected via `ConnectionApiKeysProviding`.

**Heuristic:** if the helper would make sense in upstream `substrate-sdk-ios`, it belongs in `SubstrateSdkExt`.

### 5b. Inherited/ Migration Policy

`polkadot-app/Inherited/` is legacy code being drained opportunistically:
- **Migrate the file you're touching**, not a directory at a time — if your PR modifies `Inherited/X`, move `X` to its proper home as part of that PR
- **Don't extend** `Inherited/` with new files
- **No big-bang refactors** — dedicated "drain Inherited/" PRs are not scheduled work
- Destination depends on what the code knows (see table above): generic Substrate helpers → `SubstrateSdkExt`, chain-aware → `ChainRegistry`, app-only → `Common/`

### 5a. Don't Create Unnecessary Abstractions

- Don't add provider/wrapper classes when the service can be configured directly
- Don't add caching for runtime constants or cheap computations
- Don't create factories that just delegate to a single network fetch — collapse into the service
- Don't pass parameters that aren't used by the function's core operation

### 6. File Size Discipline

- Split files approaching ~500 lines
- Large files are consistently flagged in reviews: "this file is already quite big, makes sense to move it?"
- Place private methods in separate Swift extensions

### 7. Non-Optional Services

Services passed to coordinators/managers must be non-optional if they are always expected to exist. Optional service properties are an anti-pattern when the service is a hard dependency.

### 8. Don't Block Users Unnecessarily

- Separate async setup from required startup
- Don't `await` network when cached data is available
- Provide UI hints during async operations ("waiting for prize draw")

### 9. Adopt Structured Concurrency

When touching legacy Operation-iOS code, prefer migrating to async/await:
- Use `asyncExecute` to bridge operations to structured concurrency
- Use `StructuredConcurrency` package utilities
- Use `AsyncStream` wrappers instead of legacy subscriber/observer patterns

### 10. Localize All User-Visible Strings

All strings shown to users must go through localization. Hardcoded strings in views are flagged in reviews.

### 11. Disable Features at the Factory/Registration Level

When temporarily disabling a feature, do it at the registration/factory level — don't create the component at all. Don't insert `return nil` inside the feature's methods:

```swift
// GOOD: Don't create the extension if not needed
// In ChatExtensionsRegistry.createDimExtensions:
// simply skip creating mobRule for W3S

// BAD: Early return inside the feature
func someFeatureMethod() -> Result? {
    return nil // Anti-pattern: partially-initialized feature
}
```

Use feature flags (`#if UNSTABLE`, `#if F_DEV`, `#if TESTNET_FEATURE`, W3S flags) for temporary behavior changes.

### 12. Use Type Aliases for Domain Concepts

Use typed aliases instead of raw `String` for domain-specific parameters:

```swift
// GOOD
func fetchProduct(by id: ProductId) -> Product

// BAD
func fetchProduct(by id: String) -> Product
```

(review: "use ProductId alias instead of String")

### 13. Parse at API Boundaries

When receiving data from JS bridge, host API, or external sources, parse into typed Swift models immediately at the boundary:

```swift
// GOOD: Parse at boundary
let request = try JSONDecoder().decode(ScheduledNotificationRequest.self, from: data)

// BAD: Pass raw dictionaries deeper into code
func handleNotification(params: [String: Any]) { ... }
```

### 13a. TODOs for Pending Integrations

When wiring an integration that depends on something not yet available (e.g., TURN node configuration from backend, an upcoming endpoint, a placeholder secret), leave an explicit `// TODO:` with the owning area and the unblocking condition. Don't ship silent placeholders — a reviewer or future reader should be able to grep for the TODO and know exactly what's missing.

### 14. Configuration Values in AppConfig

URLs, API endpoints, and other configuration values must go into `AppConfig` — not hardcoded in ViewFactory or module files.

### 15. Inject Logger Through Init

Don't reach for `Logger.shared` inside service/interactor methods. Take the logger as a constructor parameter so tests can substitute it and so the dependency graph stays explicit. Singleton access scattered through method bodies is a recurring review smell.

```swift
// GOOD
final class FooService {
    private let logger: LoggerProtocol
    init(logger: LoggerProtocol) { self.logger = logger }
}

// BAD
final class FooService {
    func work() { Logger.shared.error("…") }
}
```

### 16. Don't Expose Internal Services Through Protocol Properties

When a service owns sub-services, wire them internally during setup rather than exposing them:

```swift
// GOOD: Setup internally
protocol CoinageServicing {
    func setup(context: DenominationContext)
}

// BAD: Exposing sub-service
protocol CoinageServicing {
    var externalPaymentService: PaymentService { get set }
}
```

## Mid-Migration Subsystems

These areas have old and new patterns coexisting. New code follows the north-star:

| Subsystem              | Legacy Pattern                  | North-Star Pattern                    |
|------------------------|---------------------------------|---------------------------------------|
| Networking             | Operation-iOS chains            | Structured concurrency (async/await)  |
| Reactive streams       | Subscriber/observer             | AsyncExtensions / AsyncStream         |
| Legacy code            | `Inherited/` directory          | Migrated to `Common/` or packages opportunistically |
| Chain registry         | App-level `ChainRegistry`       | `Packages/ChainRegistry` consumed via `ChainRegistryFacade` |
| Event center           | In-app singleton + visitor      | `Packages/EventCenter` shared by app + packages |
| Storage                | Direct CoreData access          | Repository pattern with mappers       |

## Build Configuration Guards

- SDKs like Sentry should not run in unit tests or preview builds
- Guard with environment checks (isRunningTests, isPreview)
- Build scripts should also be gated per configuration (Debug excluded)
- Build phase scripts for symbol upload (e.g., Sentry dSYMs) must exclude Debug configuration

## Build Variant Feature Flags

| Flag               | Purpose                                        |
|--------------------|-------------------------------------------------|
| `#if UNSTABLE`     | Preview/testnet chain configurations            |
| `#if F_DEV`        | Development bundle identifier prefix            |
| `#if TESTNET_FEATURE` | Gates testnet-only UI features               |
| W3S flags          | Temporary event-specific behavior               |

Gate temporary behavior changes behind feature flags rather than unconditional code changes.
