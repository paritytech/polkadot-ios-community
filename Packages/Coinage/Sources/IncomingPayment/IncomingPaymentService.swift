import AsyncExtensions
import Foundation
import os
import SDKLogger
import SubstrateSdk

/// Drives inbound top-ups to completion, restart-durably. `accept` validates and persists; the
/// `setup` subscription starts/resumes the claim task, so idempotency and recovery fall out of
/// persistence (mirrors `MixnetUploadService`).
///
/// Secrets live only in `IncomingPaymentSecretStoring` (encrypted, wiped on settle); the record holds
/// no source and no live status. The terminal verdict is written once on settle and read back
/// exactly, so a reorg after settlement can never change what a completed top-up reports.
public final class IncomingPaymentService: IncomingPaymentServicing, @unchecked Sendable {
    private let store: any IncomingPaymentStoring
    private let secretStore: any IncomingPaymentSecretStoring
    private let sourceResolver: any IncomingPaymentSourceResolving
    private let paymentContext: IncomingPaymentContext
    private let claimCoinsService: any ClaimCoinsServicing
    private let claimAssetService: any ClaimAssetServicing
    private let txService: any CoinageTxServicing
    private let contextProvider: any DenominationContextProviding
    private let acknowledger: any IncomingPaymentAcknowledging
    private let instanceId: CoinageInstanceId
    private let logger: SDKLoggerProtocol?

    private let setupTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(
        store: any IncomingPaymentStoring,
        secretStore: any IncomingPaymentSecretStoring,
        sourceResolver: any IncomingPaymentSourceResolving,
        paymentContext: IncomingPaymentContext,
        claimCoinsService: any ClaimCoinsServicing,
        claimAssetService: any ClaimAssetServicing,
        txService: any CoinageTxServicing,
        contextProvider: any DenominationContextProviding,
        acknowledger: any IncomingPaymentAcknowledging,
        instanceId: CoinageInstanceId,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.secretStore = secretStore
        self.sourceResolver = sourceResolver
        self.paymentContext = paymentContext
        self.claimCoinsService = claimCoinsService
        self.claimAssetService = claimAssetService
        self.txService = txService
        self.contextProvider = contextProvider
        self.acknowledger = acknowledger
        self.instanceId = instanceId
        self.logger = logger
    }
}

// MARK: - IncomingPaymentServicing

public extension IncomingPaymentService {
    func accept(
        amount: Balance,
        descriptor: IncomingPaymentSourceDescriptor,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws {
        do {
            try await performAccept(amount: amount, descriptor: descriptor, paymentId: paymentId, productId: productId)
        } catch let error as IncomingPaymentError {
            throw error
        } catch {
            throw IncomingPaymentError.unknown(reason: error.localizedDescription)
        }
    }

    func subscribeStatus(
        for paymentId: IncomingPaymentId,
        productId: String
    ) async -> AnyAsyncSequence<IncomingPaymentStatus> {
        let groupId = IncomingPayment.groupId(productId: productId, paymentId: paymentId)

        if let live = await paymentContext.liveStatusStream(for: groupId) {
            return live
        }

        // Cold subscribe: a settled record returns its stored verdict exactly; an unknown one, notClaimed.
        let payment = try? await store.fetch(groupId: groupId)
        guard let payment else {
            return await paymentContext.seededStatusStream(.notClaimed, for: groupId)
        }

        let status = payment.outcome.map(IncomingPaymentStatus.init(outcome:)) ?? .detecting
        return await paymentContext.seededStatusStream(status, for: groupId)
    }

    func setup() {
        let task = Task { [weak self] in
            guard let self else { return }
            await runSetup()
        }
        setupTask.withLock { current in
            current?.cancel()
            current = task
        }
    }

    func throttle() {
        let task = setupTask.withLock { current -> Task<Void, Never>? in
            let previous = current
            current = nil
            return previous
        }
        task?.cancel()

        Task { [paymentContext] in
            await paymentContext.cancelAll()
        }
    }
}

// MARK: - Accept

private extension IncomingPaymentService {
    func performAccept(
        amount: Balance,
        descriptor: IncomingPaymentSourceDescriptor,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws {
        let groupId = IncomingPayment.groupId(productId: productId, paymentId: paymentId)
        if try await store.fetch(groupId: groupId) != nil {
            throw IncomingPaymentError.alreadyExists
        }

        // Validate by resolving — a source that cannot produce signing/claim material is invalid.
        do {
            _ = try await sourceResolver.resolve(productId: productId, descriptor: descriptor)
        } catch {
            throw IncomingPaymentError.invalidSource(reason: error.localizedDescription)
        }

        try await ensureSourceFree(descriptor: descriptor, productId: productId)

        // Both recorded before a single transaction is built, so a resumed top-up can be picked up.
        try secretStore.save(groupId: groupId, descriptor: descriptor)

        let payment = IncomingPayment(
            paymentId: paymentId,
            productId: productId,
            amount: amount,
            createdAt: Date(),
            outcome: nil
        )
        do {
            try await store.save(payment)
        } catch {
            secretStore.remove(groupId: groupId)
            throw error
        }
    }

    /// Throws `SourceBusy` when the descriptor draws on the same funds as an active payment's.
    func ensureSourceFree(descriptor: IncomingPaymentSourceDescriptor, productId: String) async throws {
        let active = try await store.fetchActivePayments()
        for other in active {
            guard let otherDescriptor = secretStore.fetch(groupId: other.groupId) else { continue }
            if descriptor.drawsOnSameFunds(as: otherDescriptor, sameProduct: other.productId == productId) {
                throw IncomingPaymentError.sourceBusy
            }
        }
    }
}

// MARK: - Setup / driving

private extension IncomingPaymentService {
    func runSetup() async {
        let denomination: DenominationBreakdownContext
        do {
            denomination = try await contextProvider.denominationContext()
        } catch {
            logger?.error("Incoming payments: denomination context unavailable: \(error)")
            return
        }

        do {
            for try await payments in store.observeActivePayments() {
                for payment in payments {
                    await paymentContext.process(
                        groupId: payment.groupId,
                        run: runClosure(for: payment, denomination: denomination)
                    )
                }
            }
        } catch {
            logger?.error("Incoming payments: active-payment stream failed: \(error)")
        }
    }

    func runClosure(
        for payment: IncomingPayment,
        denomination: DenominationBreakdownContext
    ) -> @Sendable () -> Task<Void, Never> {
        { [weak self] in
            Task { [weak self] in
                await self?.drive(payment: payment, denomination: denomination)
            }
        }
    }

    func drive(payment: IncomingPayment, denomination: DenominationBreakdownContext) async {
        defer { Task { [paymentContext, groupId = payment.groupId] in await paymentContext.finish(groupId: groupId) } }

        // Secret gone (Keychain lost): can't re-run, so settle from the ledger.
        guard let descriptor = secretStore.fetch(groupId: payment.groupId) else {
            let status = await verdictFromDurability(payment)
            await paymentContext.report(status, for: payment.groupId)
            await settle(payment: payment, finalStatus: status)
            return
        }

        let resolved: ResolvedIncomingSource
        do {
            resolved = try await sourceResolver.resolve(productId: payment.productId, descriptor: descriptor)
        } catch {
            logger?.error("Incoming payment \(payment.paymentId) source unresolvable; will retry: \(error)")
            return
        }

        var last: IncomingPaymentStatus = .detecting
        do {
            for try await detection in claimStream(for: payment, resolved: resolved, denomination: denomination) {
                last = IncomingPaymentStatus(detection: detection)
                await paymentContext.report(last, for: payment.groupId)
            }
        } catch {
            logger?.error("Incoming payment \(payment.paymentId) claim stream failed: \(error)")
        }
        await settle(payment: payment, finalStatus: last)
    }

    func claimStream(
        for payment: IncomingPayment,
        resolved: ResolvedIncomingSource,
        denomination: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        let retryUntil = payment.createdAt.addingTimeInterval(CoinageConstants.topUpRetryWindow)

        switch resolved {
        case let .coins(secretKeys):
            return claimCoinsService.claim(
                coinKeys: secretKeys,
                groupId: payment.groupId,
                retryUntil: retryUntil,
                context: denomination
            )
        case let .wallet(wallet):
            return claimAssetService.claim(
                wallet: wallet,
                amount: payment.amount,
                groupId: payment.groupId,
                retryUntil: retryUntil,
                instanceId: instanceId,
                context: denomination
            )
        }
    }

    /// Writes the verdict, wipes the secret, and prompts the user on an unhappy ending. A run that
    /// ended without a verdict (window not yet closed) is left for the next launch to resume.
    func settle(payment: IncomingPayment, finalStatus: IncomingPaymentStatus) async {
        guard let outcome = finalStatus.terminalOutcome else {
            logger?.warning("Incoming payment \(payment.paymentId) ended without a verdict: \(finalStatus)")
            return
        }

        do {
            try await store.settle(groupId: payment.groupId, outcome: outcome)
        } catch {
            logger?.error("Incoming payment \(payment.paymentId) failed to persist verdict: \(error)")
        }
        secretStore.remove(groupId: payment.groupId)

        switch outcome {
        case .claimedPartially,
             .notClaimed:
            await acknowledger.acknowledge(
                productId: payment.productId,
                paymentId: payment.paymentId,
                requestedAmount: payment.amount,
                outcome: outcome
            )
        case .claimed:
            break
        }
    }

    /// Best-effort verdict for a payment whose secret is gone, from the durability group snapshot.
    /// Empty group ⇒ nothing was loaded ⇒ `.notClaimed`; otherwise its finalization state (the exact
    /// partial figure is not reconstructed here — a rare post-loss path).
    func verdictFromDurability(_ payment: IncomingPayment) async -> IncomingPaymentStatus {
        let entries = await (try? txService.getOperationGroupStatuses(payment.groupId)) ?? []
        guard !entries.isEmpty else { return .notClaimed }
        return entries.allSatisfy { $0.status == .finalizedSuccess } ? .claimed(finalized: true) : .notClaimed
    }
}
