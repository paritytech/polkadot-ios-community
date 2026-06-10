# Building, configuring & publishing

This guide explains how to configure the app, sign it, and distribute it to
**TestFlight** and **Firebase App Distribution**.

> This repository intentionally ships **no hosted CI/CD pipeline and no Fastlane
> implementation**. What follows is a vendor-neutral description of how to
> configure, sign and distribute the app with standard Apple and Google tooling,
> plus the lightweight scripts included in this repo. Wire it into whichever CI
> system you prefer (GitHub Actions, GitLab CI, Bitrise, Xcode Cloud, …).

---

## 1. How configuration works

Build-time secrets, links and a few endpoints are externalised into
**environment variables** that are baked into the app at build time (most
backend endpoints come from Firebase Remote Config instead — see
`RemoteAppConfig`). There are three pieces:

| File | Committed? | Purpose |
|------|-----------|---------|
| `Scripts/inject-keys.sh` | ✅ yes | Generates the Swift below. Carries the non-secret placeholder defaults inline. |
| `polkadot-app/env-vars.sh` | ❌ gitignored | Your secrets and local overrides. Created from `env-vars.sh.template`. |
| `polkadot-app/CIKeys.generated.swift` | ❌ gitignored | Generated Swift read by the app. Produced by `Scripts/inject-keys.sh`. |

Resolution order (highest priority first): **environment / `env-vars.sh` →
inline defaults in `inject-keys.sh`**.

Run it manually whenever the configuration changes (Xcode also runs it as a
scheme pre-action):

```bash
./Scripts/inject-keys.sh
```

### First-time local setup

```bash
./Scripts/setup-secrets.sh
```

This scaffolds `env-vars.sh` and the `GoogleService-Info` plists from their
`*.template` files (without overwriting anything that already exists) and
generates `CIKeys.generated.swift`. The app then builds and runs with safe
public defaults; features that need a real secret stay disabled until you
provide one.

> **In CI:** instead of `env-vars.sh`, export the variables directly into the job
> environment (from your secret store) and run `./Scripts/inject-keys.sh` before
> building. Exported environment variables take precedence over the committed
> defaults automatically.

---

## 2. Environment variables

### Secrets — set these in `polkadot-app/env-vars.sh` or the CI environment

| Variable | Used for | If empty |
|----------|----------|----------|
| `W3S_AUTH_KEY` | Web3 Summit authorisation seed (hex) | W3S signing disabled |
| `POSTHOG_API_KEY` | PostHog product analytics project key (`phc_…`) | Analytics disabled |
| `SENTRY_DSN` | Sentry crash/issue reporting DSN | Issue monitoring disabled |
| `MELD_BASIC_AUTH_TOKEN` | Meld fiat on-ramp basic auth (`<key>:<secret>`) | Fiat on-ramp auth unset |

### Signing & distribution — set in the CI environment (not needed for local simulator runs)

| Variable | Used for |
|----------|----------|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID (TestFlight upload, signing) |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_KEY_CONTENT` | The `.p8` private key (base64 or raw) |
| `FIREBASE_APP_ID` | Firebase App Distribution app ID (`1:…:ios:…`) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Google service-account JSON for App Distribution |
| `FIREBASE_GROUPS` | Comma-separated tester groups |
| `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` | Uploading dSYMs to Sentry (build phase skips when unset) |

> Variable names above are conventions, not contracts — name them however your
> chosen tooling expects. The app itself only reads the variables in the first
> table (via `inject-keys.sh`); the second table is consumed by signing/upload
> tools you invoke yourself.

### Non-secret config — defaults inlined in `Scripts/inject-keys.sh`, override only if needed

| Variable | What it is / where it's used |
|----------|------------------------------|
| `TERMS_OF_USE_LINK` | Terms of Use page opened from Settings/onboarding. |
| `PRIVACY_POLICY_LINK` | Privacy Policy page opened from Settings/onboarding. |
| `CONTACT_EMAIL` | Support contact email opened from Settings. |
| `REPORT_ISSUE_EMAIL` | Recipient of the in-app "report issue" mail draft (Proof of Ink tattoo upload). |
| `LOGS_EMAIL` | Recipient of the in-app diagnostic-logs mail draft (Debug Settings → send logs). |
| `GAME_RESULTS_FALLBACK_URL` | Fallback URL for DIM2 game results when a per-game URL is absent. Weekly-game results in chat. |
| `MELD_BASE_URL` | Meld API base URL. Fiat on-ramp (buy crypto). |
| `COINGECKO_BASE_URL` | CoinGecko API base URL. Token price / market data. |
| `POSTHOG_HOST` | PostHog ingestion host. Product analytics (paired with `POSTHOG_API_KEY`). |

Most apps only override these when pointing a build at different
infrastructure. Backend and on-chain endpoints (identity backend, IPFS gateway,
DotNS resolver, Web3 Summit, game dashboard) are not build-time variables: the
app fetches them at runtime via Firebase Remote Config (see `RemoteAppConfig`
and `FirebaseApplicationService`).

---

## 3. Firebase setup

The app uses Firebase for Remote Config. The real
`GoogleService-Info.plist` files are **not** committed.

1. Create a Firebase project and register two iOS apps — one for development
   (bundle id `…​.develop`) and one for production.
2. Download each `GoogleService-Info.plist` and save them as:
   - `polkadot-app/GoogleService/GoogleService-Info-Dev.plist`
   - `polkadot-app/GoogleService/GoogleService-Info-Release.plist`
3. During a build, the **"Google info"** build phase copies the correct one to
   `polkadot-app/GoogleService-Info.plist` based on `$CONFIGURATION`
   (Debug/Dev/DevCI → Dev, Release/Nightly → Release). In CI (`RUN_IN_CI=true`)
   this copy is skipped — provide the active plist yourself.

`*.plist.template` files document the expected structure with placeholder values.

---

## 4. Build configurations

| Configuration | Bundle id | Environment |
|---------------|-----------|-------------|
| `Debug` / `DevCI` | `…​.develop` | Unstable preview backend |
| `Nightly` | production id | Stable testnet — distributed via TestFlight |
| `Release` | production id | Mainnet |

Bundle ids, app name, icon and deep-link scheme live in
`polkadot-app/Configs/*.xcconfig` and
`NotificationServiceExtension/Configs/*.xcconfig`. Change them to your own
identifiers before distributing.

---

## 5. Code signing

You need an Apple Developer account and a registered App ID for the app **and**
its `NotificationServiceExtension`.

Recommended: **App Store Connect API key** (`.p8`) for non-interactive signing
and uploads. Generate one in App Store Connect → Users and Access → Integrations
→ Keys, and expose it to CI as `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_CONTENT`.

For certificates and provisioning profiles, pick one of:

- **Xcode automatic signing** — simplest for local builds and Xcode Cloud.
- **A shared signing repo** (e.g. Fastlane `match`) — store certs/profiles
  encrypted in a private git repo; each machine/CI runner fetches them. `match`
  works with any private repo you control.
- **Manual** — export a Distribution certificate (`.p12`) and the provisioning
  profiles, import them into the build keychain in CI.

In CI, create a dedicated keychain, import the certificate, and select the right
provisioning profile via the export options when archiving.

---

## 6. Build & archive

```bash
# Generate build-time config
./Scripts/inject-keys.sh

# Archive
xcodebuild -project polkadot-app.xcodeproj \
  -scheme polkadot-app \
  -configuration Release \
  -archivePath build/polkadot-app.xcarchive \
  archive

# Export a signed .ipa (provide an ExportOptions.plist describing the method,
# team id and provisioning profiles)
xcodebuild -exportArchive \
  -archivePath build/polkadot-app.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/
```

A minimal `ExportOptions.plist` for App Store distribution:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
```

Use `method = ad-hoc` (or `development`) for Firebase App Distribution builds.

---

## 7. Distribute to TestFlight

After exporting an App Store `.ipa`, upload it with Apple's notarised tool using
your App Store Connect API key:

```bash
xcrun altool --upload-app -f build/polkadot-app.ipa -t ios \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
```

(`xcrun altool` reads the `.p8` from `~/.appstoreconnect/private_keys/` or
`./private_keys/`. `xcrun notarytool`/`Transporter` are alternatives.)

The build then appears in App Store Connect → TestFlight. Add it to internal or
external tester groups there, or automate group assignment with the App Store
Connect API.

---

## 8. Distribute to Firebase App Distribution

Build an `ad-hoc` signed `.ipa`, then upload with the Firebase CLI:

```bash
firebase appdistribution:distribute build/polkadot-app.ipa \
  --app "$FIREBASE_APP_ID" \
  --groups "$FIREBASE_GROUPS" \
  --release-notes "Your release notes"
```

Authenticate the CLI with a Google service account that has the **Firebase App
Distribution Admin** role (`GOOGLE_APPLICATION_CREDENTIALS` pointing at the
service-account JSON, or `--service-credentials-file`).

---

## 9. Crash symbols (Sentry)

Sentry is disabled for `Release` builds — the SDK is only compiled into
`TESTNET_FEATURE` configurations (`Debug`/`DevCI`/`Nightly`). Accordingly, the
**"Upload Debug Symbols to Sentry"** Xcode build phase uploads dSYMs only on
`DevCI` and `Nightly` builds and skips `Debug` and `Release`. It also requires
`SENTRY_ORG` and `SENTRY_PROJECT` to be set (and `sentry-cli` installed with
`SENTRY_AUTH_TOKEN` configured); otherwise it skips silently. Leave them unset
to disable Sentry uploads entirely.

The repo also ships a `.mcp.json.template` that registers the **Sentry MCP
server** for AI tooling (e.g. Claude Code). It embeds an organisation-specific
Sentry org/project, so the real `.mcp.json` is gitignored. `setup-secrets.sh`
scaffolds it from the template; edit the URL to your own
`…/mcp/<org>/<project>`. This is optional and unrelated to building the app.

---

## 10. Wiring it into CI

A typical distribution job:

1. Check out the repo, install Xcode and SwiftPM dependencies.
2. Export secrets from your secret store into the environment.
3. Provide the real `GoogleService-Info` plists.
4. Run `./Scripts/inject-keys.sh`.
5. Import signing certificate + profile into a CI keychain.
6. `xcodebuild archive` → `xcodebuild -exportArchive`.
7. Upload to TestFlight (`xcrun altool`) or Firebase (`firebase appdistribution`).

Keep every credential in your CI provider's secret store — never commit
`env-vars.sh`, the real `GoogleService-Info` plists, signing certificates, or API
keys.
