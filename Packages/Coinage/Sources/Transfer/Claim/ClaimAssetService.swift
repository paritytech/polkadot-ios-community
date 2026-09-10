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
    /// The pacing of one claim. Injected so tests need not wait out production delays.
    struct Timing: Sendable {
        /// How long one pass waits for a fresh balance look before loading against the last one seen.
        /// This is the only pacing between attempts, so a failing load retries at this cadence.
        let detectionTimeout: Duration
        /// How long a dropped balance subscription waits before it is opened again.
        let resubscribeDelay: Duration

        static let production = Timing(detectionTimeout: .seconds(30), resubscribeDelay: .seconds(1))
    }

    private let assetsTracking: any AssetsTracking
    private let voucherLoaderFactory: any VoucherLoaderFactoryProtocol
    private let voucherService: any VoucherServiceProtocol
    private let txService: any CoinageTxServicing
    private let timing: Timing
    private let logger: SDKLoggerProtocol?

    init(
        assetsTracking: any AssetsTracking,
        voucherLoaderFactory: any VoucherLoaderFactoryProtocol,
        voucherService: any VoucherServiceProtocol,
        txService: any CoinageTxServicing,
        timing: Timing = .production,
        logger: SDKLoggerProtocol?
    ) {
        self.assetsTracking = assetsTracking
        self.voucherLoaderFactory = voucherLoaderFactory
        self.voucherService = voucherService
        self.txService = txService
        self.timing = timing
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

        // Balance looks are consumed once, so a failing load cannot spin the loop off the same look.
        let balanceLooks = AsyncBufferedChannel<Balance>()
        let pump = Task { await self.pumpBalance(into: balanceLooks, instanceId: instanceId, accountId: accountId) }
        defer { pump.cancel() }
        let looks = balanceLooks.makeAsyncIterator()

        var settled: [CoinageTxEntry] = []
        var lastSeen: Balance = 0

        logger?.debug("Will start claim for group=\(groupId) amount=\(amount)")

        while !Task.isCancelled {
            settled = await awaitKnownOperationsSettled(
                groupId: groupId, amount: amount, context: context, report: report
            )

            let claimed = await valueClaimed(settled.finalizedSuccess(), context: context)
            let remaining = amount > claimed ? amount - claimed : 0

            logger?.debug("Claimed \(claimed) of \(amount), remaining \(remaining) for group=\(groupId)")

            if remaining == 0 { break }

            // Below the smallest denomination nothing can ever load it, however much more arrives.
            if context.breakdown(amountInPlanks: remaining).isEmpty {
                logger?.debug("Claim asset: remainder \(remaining) is unloadable group=\(groupId)")
                break
            }

            // Checked before attempting: the funds are the caller's own and nothing else will spend
            // them, so a window that closed on them is the end of it (mirrors Android).
            if Date() >= retryUntil {
                logger?.debug("Claim asset: window closed group=\(groupId) claimed=\(claimed)")
                break
            }

            lastSeen = await awaitBalance(looks, lastSeen: lastSeen, target: remaining)
            let loadable = Swift.min(lastSeen, remaining)

            guard loadable > 0 else { continue }

            report(.claiming)
            logger?.debug("Claiming \(loadable) for group=\(groupId)")
            await load(wallet: wallet, amount: loadable, groupId: groupId, context: context)
        }

        let verdict = await toVerdict(settled, amount: amount, context: context)

        logger?.debug("Claiming completed: verdict=\(verdict) group=\(groupId)")

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
    ) async {
        do {
            let loader = try voucherLoaderFactory.makeLoader(for: wallet)
            _ = try await loader.load(amount: amount, breakdownContext: context, groupId: groupId)
        } catch {
            logger?.error("Claim asset: voucher load failed group=\(groupId): \(error)")
        }
    }
}

// MARK: - Detection

private extension ClaimAssetService {
    /// Feeds every balance look into `channel` until cancelled, reopening the subscription after
    /// ``Timing/resubscribeDelay`` whenever it fails or ends. A tracker that cannot be opened at all
    /// therefore feeds nothing, and the loop runs out its window on the last balance seen.
    func pumpBalance(
        into channel: AsyncBufferedChannel<Balance>,
        instanceId: CoinageInstanceId,
        accountId: AccountId
    ) async {
        while !Task.isCancelled {
            do {
                let stream = try await assetsTracking.track(instanceId: instanceId, accountId: accountId)
                for try await balance in stream {
                    channel.send(balance)
                }
            } catch {
                logger?.error("Claim asset: balance tracking failed for instance=\(instanceId): \(error)")
            }

            guard await (try? Task.sleep(for: timing.resubscribeDelay)) != nil else { break }
        }
        channel.finish()
    }

    /// The newest balance look within ``Timing/detectionTimeout``, stopping early once it covers
    /// `target`; `lastSeen` when no fresh look arrives in time. The newest look wins outright even when
    /// smaller: the account can be spent from elsewhere.
    func awaitBalance(
        _ looks: AsyncBufferedChannel<Balance>.Iterator,
        lastSeen: Balance,
        target: Balance
    ) async -> Balance {
        let latest = OSAllocatedUnfairLock<Balance>(initialState: lastSeen)
        _ = try? await withTimeout(timing.detectionTimeout) {
            while let balance = await looks.next() {
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
        return .verdict(finalized: value, of: amount)
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
