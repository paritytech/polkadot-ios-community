import AsyncExtensions
import BigInt
import Foundation
import KeyDerivation
import os
import SDKLogger
import StructuredConcurrency
import SubstrateSdk

/// Claims an external asset a peer funded into a wallet we hold the key to, by loading recycler
/// vouchers for it.
///
/// Like `ClaimCoinsService`, it is driven off the durability group registered under `groupId` and
/// retries until the full amount is claimed or `retryUntil` passes: it first awaits any operations
/// already registered for the group to settle (so a resumed claim watches a prior run's load instead
/// of re-submitting it), then, while short of the amount, detects newly-arrived balance and loads
/// vouchers for the remainder. Completion of the flow tells a caller the payment is finished.
public protocol ClaimAssetServicing: Sendable {
    func claim(
        wallet: any WalletManaging,
        amount: Balance,
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        instanceId: CoinageInstanceId,
        context: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection>
}

public final class ClaimAssetService: ClaimAssetServicing, @unchecked Sendable {
    /// How long to wait for funded asset to appear on each pass before claiming what is there.
    private static let detectionTimeout: Duration = .seconds(30)

    private let assetsTracking: any AssetsTracking
    private let voucherLoaderFactory: any VoucherLoaderFactoryProtocol
    private let voucherService: any VoucherServiceProtocol
    private let txService: any CoinageTxServicing
    private let logger: SDKLoggerProtocol?

    init(
        assetsTracking: any AssetsTracking,
        voucherLoaderFactory: any VoucherLoaderFactoryProtocol,
        voucherService: any VoucherServiceProtocol,
        txService: any CoinageTxServicing,
        logger: SDKLoggerProtocol?
    ) {
        self.assetsTracking = assetsTracking
        self.voucherLoaderFactory = voucherLoaderFactory
        self.voucherService = voucherService
        self.txService = txService
        self.logger = logger
    }

    public func claim(
        wallet: any WalletManaging,
        amount: Balance,
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        instanceId: CoinageInstanceId,
        context: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        AsyncStream { continuation in
            let task = Task {
                await self.runClaim(
                    wallet: wallet,
                    amount: amount,
                    groupId: groupId,
                    retryUntil: retryUntil,
                    instanceId: instanceId,
                    context: context
                ) { detection in
                    continuation.yield(detection)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        .eraseToAnyAsyncSequence()
    }
}

// MARK: - Claim loop

private extension ClaimAssetService {
    func runClaim(
        wallet: any WalletManaging,
        amount: Balance,
        groupId: CoinageTxGroupId,
        retryUntil: Date,
        instanceId: CoinageInstanceId,
        context: DenominationBreakdownContext,
        report: @Sendable (CoinageTransferDetection) -> Void
    ) async {
        report(.detecting)

        guard let accountId = try? wallet.getRawPublicKey() else {
            logger?.error("Claim asset: invalid wallet for group=\(groupId)")
            report(.notClaimed)
            return
        }

        var settled: [CoinageTxEntry] = []

        logger?.debug(
            "Will start claim for group=\(groupId) amount=\(amount)"
        )

        while !Task.isCancelled {
            logger?.debug("Awaiting known operations for group=\(groupId)")

            // Await operations already registered under this group (resume-safe), reporting progress.
            settled = await awaitKnownOperationsSettled(
                groupId: groupId, amount: amount, context: context, report: report
            )

            logger?.debug("Awaiting claimed amount for group=\(groupId)")

            let claimed = await valueClaimed(settled.finalizedSuccess(), context: context)

            logger?.debug("Received claimed amount=\(claimed), group=\(groupId)")

            let remaining = amount > claimed ? amount - claimed : 0
            if remaining == 0 {
                logger?.debug("All claimed, exiting claim loop for group=\(groupId)")
                break
            }

            logger?.debug("Waiting for remained amount=\(remaining) for group=\(groupId)")

            // Detect the still-unloaded balance and load vouchers for the remainder.
            let observed = await awaitBalance(instanceId: instanceId, accountId: accountId, target: remaining)
            let loadable = Swift.min(observed, remaining)

            logger?.debug("Loaded \(loadable) for group=\(groupId)")

            if loadable > 0 {
                report(.claiming)

                logger?.debug("Claiming \(loadable) for group=\(groupId)")
                _ = await load(wallet: wallet, amount: loadable, groupId: groupId, context: context)
            } else if Date() >= retryUntil {
                logger?.debug("Claim asset: window closed group=\(groupId) claimed<amount")
                break
            }
        }

        let verdict = await toVerdict(settled, amount: amount, context: context)

        logger?.debug("Claming completed: verdict=\(verdict) group=\(groupId)")

        report(verdict)
    }

    /// Reports the group on every ledger update until nothing in it is live, then returns what it
    /// settled on — mirrors `ClaimCoinsService.awaitKnownOperationsSettled`. An empty group returns
    /// immediately (`allSatisfy` over no entries is `true`), the "not loaded yet" signal.
    func awaitKnownOperationsSettled(
        groupId: CoinageTxGroupId,
        amount: Balance,
        context: DenominationBreakdownContext,
        report: @Sendable (CoinageTransferDetection) -> Void
    ) async -> [CoinageTxEntry] {
        var last: [CoinageTxEntry] = []
        do {
            for try await states in txService.subscribeOperationGroupStatuses(groupId) {
                last = states
                await report(toProgress(states, amount: amount, context: context))
                if states.allSatisfy({ !$0.status.isLive }) { break }
            }
        } catch {
            logger?.error("Claim asset: group-status stream failed group=\(groupId): \(error)")
        }
        return last
    }

    /// Loads recycler vouchers for `amount` under `groupId`. The durability layer retries failed
    /// batches, so callers derive value from the settled group rather than this call's success.
    func load(
        wallet: any WalletManaging,
        amount: Balance,
        groupId: CoinageTxGroupId,
        context: DenominationBreakdownContext
    ) async -> Bool {
        do {
            let loader = try voucherLoaderFactory.makeLoader(for: wallet)
            _ = try await loader.load(amount: amount, breakdownContext: context, groupId: groupId)
            return true
        } catch {
            logger?.error("Claim asset: voucher load failed group=\(groupId): \(error)")
            return false
        }
    }
}

// MARK: - Detection

private extension ClaimAssetService {
    /// The latest balance seen within ``detectionTimeout``, stopping early once it covers `target`.
    func awaitBalance(instanceId: CoinageInstanceId, accountId: AccountId, target: Balance) async -> Balance {
        let latest = OSAllocatedUnfairLock<Balance>(initialState: 0)
        _ = try? await withTimeout(Self.detectionTimeout) { [assetsTracking] in
            let stream = try await assetsTracking.track(instanceId: instanceId, accountId: accountId)
            for try await balance in stream {
                latest.withLock { $0 = balance }
                if balance >= target { break }
            }
        }
        return latest.withLock { $0 }
    }
}

// MARK: - Detection verdicts

private extension ClaimAssetService {
    /// What is true right now, reported on every ledger update. A shortfall is never announced here —
    /// only `toVerdict` may say claiming is over — so `claimed` is surfaced only once the full amount
    /// has arrived.
    func toProgress(
        _ states: [CoinageTxEntry],
        amount: Balance,
        context: DenominationBreakdownContext
    ) async -> CoinageTransferDetection {
        guard !states.isEmpty else { return .detecting }
        guard states.allSatisfy(\.status.isArrived) else { return .claiming }

        let value = await valueClaimed(states, context: context)
        guard value >= amount else { return .claiming }

        let finalized = states.allSatisfy { $0.status == .finalizedSuccess }
        return .claimed(amount: value, finalized: finalized)
    }

    /// The last word, once nothing further will be attempted. Success only when the full amount
    /// finalized; a lesser finalized value that still claimed something is partial (source
    /// underfunded), matching the host spec.
    func toVerdict(
        _ states: [CoinageTxEntry],
        amount: Balance,
        context: DenominationBreakdownContext
    ) async -> CoinageTransferDetection {
        let value = await valueClaimed(states.finalizedSuccess(), context: context)

        if value >= amount, amount > 0 {
            return .claimed(amount: value, finalized: true)
        }
        return value > 0 ? .claimedPartially(claimed: value) : .notClaimed
    }

    /// The planks loaded by `entries` — their output vouchers, fetched by key, valued against the
    /// denomination context.
    func valueClaimed(_ entries: [CoinageTxEntry], context: DenominationBreakdownContext) async -> Balance {
        let outputKeys = entries.outputPublicKeys()
        guard !outputKeys.isEmpty else { return 0 }

        let vouchers = await (try? voucherService.fetchVouchers(publicKeys: outputKeys)) ?? []
        return vouchers.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.exponent) }
    }
}
