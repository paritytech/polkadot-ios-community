import AsyncExtensions
import Foundation
import KeyDerivation
import os
import SDKLogger
import SubstrateSdk

/// Drives inbound top-ups to completion, restart-durably. `accept` only validates and persists; the
/// `setup` subscription starts/resumes the claim task, so idempotency and recovery fall out of
/// persistence (mirrors `MixnetUploadService`). Status is derived from the durability group, never
/// stored — the record carries only a `groupId` and a `processed` flag.
public final class IncomingPaymentService: IncomingPaymentServicing, @unchecked Sendable {
    private let store: any IncomingPaymentStoring
    private let validator: any IncomingPaymentSourceValidating
    private let paymentContext: IncomingPaymentContext
    private let claimCoinsService: any ClaimCoinsServicing
    private let claimAssetService: any ClaimAssetServicing
    private let txService: any CoinageTxServicing
    private let contextProvider: any DenominationContextProviding
    private let instanceId: CoinageInstanceId
    private let logger: SDKLoggerProtocol?

    private let setupTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(
        store: any IncomingPaymentStoring,
        validator: any IncomingPaymentSourceValidating,
        paymentContext: IncomingPaymentContext,
        claimCoinsService: any ClaimCoinsServicing,
        claimAssetService: any ClaimAssetServicing,
        txService: any CoinageTxServicing,
        contextProvider: any DenominationContextProviding,
        instanceId: CoinageInstanceId,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.validator = validator
        self.paymentContext = paymentContext
        self.claimCoinsService = claimCoinsService
        self.claimAssetService = claimAssetService
        self.txService = txService
        self.contextProvider = contextProvider
        self.instanceId = instanceId
        self.logger = logger
    }
}

// MARK: - IncomingPaymentServicing

public extension IncomingPaymentService {
    func accept(
        amount: Balance,
        source: IncomingPaymentSource,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws {
        do {
            try await performAccept(amount: amount, source: source, paymentId: paymentId, productId: productId)
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

        // Cold subscribe (e.g. a processed payment after restart): re-derive terminal from durability.
        guard await (try? store.fetch(groupId: groupId)) ?? nil != nil else {
            return await paymentContext.seededStatusStream(.notClaimed, for: groupId)
        }

        let status = await deriveTerminalStatus(groupId: groupId)
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
        source: IncomingPaymentSource,
        paymentId: IncomingPaymentId,
        productId: String
    ) async throws {
        let groupId = IncomingPayment.groupId(productId: productId, paymentId: paymentId)
        if try await store.fetch(groupId: groupId) != nil {
            throw IncomingPaymentError.alreadyExists
        }

        let fingerprints = try validator.fingerprints(for: source)
        try await ensureSourceFree(fingerprints: fingerprints)

        let payment = IncomingPayment(
            paymentId: paymentId,
            productId: productId,
            source: source,
            amount: amount,
            processed: false,
            createdAt: Date()
        )
        try await store.save(payment)
    }

    /// Throws `SourceBusy` when any secret key is already used by an active (unprocessed) payment.
    func ensureSourceFree(fingerprints: Set<Data>) async throws {
        let active = try await store.fetchActivePayments()
        for other in active {
            let otherFingerprints = (try? validator.fingerprints(for: other.source)) ?? []
            if !fingerprints.isDisjoint(with: otherFingerprints) {
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
                guard let self else { return }
                do {
                    for try await detection in claimStream(for: payment, denomination: denomination) {
                        await paymentContext.report(
                            IncomingPaymentStatus(detection: detection),
                            for: payment.groupId
                        )
                    }
                } catch {
                    logger?.error("Incoming payment \(payment.paymentId) claim failed: \(error)")
                }
            }
        }
    }

    func claimStream(
        for payment: IncomingPayment,
        denomination: DenominationBreakdownContext
    ) -> AnyAsyncSequence<CoinageTransferDetection> {
        let retryUntil = payment.createdAt.addingTimeInterval(CoinageConstants.claimRetryWindow)

        switch payment.source {
        case let .coinsFromPrivateKeys(secretKeys):
            return claimCoinsService.claim(
                coinKeys: secretKeys,
                groupId: payment.groupId,
                retryUntil: retryUntil,
                context: denomination
            )
        case let .externalAssetFromWallet(secretKey):
            let wallet = DynamicDerivedWallet(secretKeyProvider: { secretKey })
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

    /// Best-effort terminal status for a processed record, from the durability group snapshot. An
    /// empty group means nothing was ever loaded → `.notClaimed`; otherwise the group's finalization
    /// state. The exact partial figure is not reconstructed here (a rare post-restart cold read).
    func deriveTerminalStatus(groupId: CoinageTxGroupId) async -> IncomingPaymentStatus {
        let entries = await (try? txService.getOperationGroupStatuses(groupId)) ?? []
        guard !entries.isEmpty else { return .notClaimed }
        return entries.allSatisfy { $0.status == .finalizedSuccess }
            ? .claimed(finalized: true)
            : .claimed(finalized: false)
    }
}
