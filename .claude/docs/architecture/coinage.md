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

A coin has:
- `derivationIndex` — unique derivation path
- `valueExponent` — coin value
- `age` — coin age/lifecycle
- `spentState` — current spending state
- `accountId` — associated account

## Key Rules

1. **Use the `KeyDerivation` package** — never hand-roll coin keypair derivation. The derivation domain must be coinage-specific (never reused across features).
2. **Zero balance handling** — properly handle zero-balance edge cases
3. **Deterministic fund amounts** — top-up affordances (the "+" fund button) must compute the resulting coin set from a deterministic plan: same input balance + same target → same coin denominations every time. Don't sample randomly, don't depend on iteration order over an unsorted set, and don't let the displayed preview drift from the amount actually submitted. The fix was switching from "pick coins as we go" to producing a stable plan up-front, then rendering and submitting from that plan.
4. **Exact-match edge in transfer planning** — when the requested amount exactly equals one of the candidate coin denominations, the planner must take the single-coin path and skip the split/unload branches. Hitting split logic with an exact match crashes because it tries to break a coin it doesn't need to. The same care applies to the "no split needed" boundary in `Coinage` transfer planning: always test the exact equality case alongside under/over.

## Transfer Planning

Transfer plans determine how coins are spent:
- Exact coins — use specific coins
- Split — divide coins for partial amounts
- Unload and split — complex multi-step transfers

## Payment Processing

- `CoinagePaymentProcessingExtension` watches on-chain events for payment confirmations
- Integrates with chat for payment request/confirmation messages
- See `architecture/chat-extension.md` for chat integration

## Seams

| Seam                    | Where                          | When to touch                    |
|-------------------------|--------------------------------|----------------------------------|
| Coin models             | `Packages/Coinage/`           | Coin structure changes           |
| Transfer planning       | `Packages/Coinage/`           | New transfer strategies          |
| Coinage UI              | `Modules/Coinage/`            | Coinage screen changes           |
| Backup sync             | ServiceCoordinator             | Backup/restore flow changes      |
