import Foundation
import ExtrinsicService
import SDKLogger
import os

/// The durability subsystem's public face.
public protocol DurabilityServicing: Sendable {
    /// Registers an entry, submits its extrinsic, and tracks it to completion.
    func submit(
        inputs: [Input],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission

    /// Submits an extrinsic for an entry already registered via `register(inputs:outputs:)`.
    ///
    /// Registration and submission are separate so a caller can claim its inputs before any
    /// network round-trip. Nothing may observe an asset the entry set does not yet explain.
    func submitRegistered(
        entryId: TransactionId,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission

    /// Releases ownership of a registered entry that will never be submitted.
    ///
    /// A caller of `register(inputs:outputs:)` owns the entry and MUST reach exactly one of
    /// `submitRegistered(entryId:builder:origin:)` or this method on every path. An entry that
    /// is neither submitted nor abandoned is skipped by every future recovery pass, so its
    /// inputs stay reserved permanently.
    func abandon(_ id: TransactionId)

    /// Registers an entry without submitting it.
    ///
    /// The caller takes ownership and MUST reach exactly one of
    /// `submitRegistered(entryId:builder:origin:)` or `abandon(_:)` on every path.
    func register(inputs: [Input], outputs: [OwnAsset]) async throws -> TransactionId

    /// Starts a recovery pass without waiting for it. Never awaited by startup: a single
    /// unresolvable entry must not hold the app for a mortality window.
    func startRecoveryPass()

    /// Starts the finalized-head trigger and runs one pass immediately.
    ///
    /// Subsumes ``startRecoveryPass()``: callers that only need the one-shot pass keep using that.
    func start()

    /// Cancels the finalized-head trigger. Safe to call when not started.
    func stop()

    func transactionStatus(_ id: TransactionId) async throws -> EntryStatus

    /// Records that a coin was given to a peer. Insert-only and irreversible: from here the
    /// coin can never enter another entry, and its payment status is derived on demand.
    func registerHandoff(_ coin: OwnAsset) async throws

    func assetStatus(_ asset: OwnAsset) async throws -> CoinageAssetState

    func assetStatuses(_ assets: [OwnAsset]) async throws -> [OwnAsset: CoinageAssetState]

    /// Appendix A status for a handed-off coin.
    func paymentStatus(of coin: OwnAsset) async throws -> CoinPaymentStatus
}

/// Owns the entry set and everything that reads or writes it.
///
/// Not an actor: most stored properties are `let` and every method suspends on its first
/// statement, so actor isolation would protect nothing while implying a serialization it cannot
/// provide. Registration is serialized by the store's transaction, and `WatchedEntrySet` carries
/// its own lock. The finalized-head trigger task handle is the one mutable piece of state,
/// guarded by a lock.
public final class DurabilityService: @unchecked Sendable {
    private let store: any DurabilityStoring
    private let chain: any DurabilityChainReading
    private let registrar: EntryRegistrar
    private let watcher: SubmissionWatcher
    private let pass: RecoveryPass
    private let trigger: FinalizedHeadTrigger
    private let paymentStatusQuery: PaymentStatusQuery
    private let logger: SDKLoggerProtocol?

    private let triggerTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(
        store: any DurabilityStoring,
        chain: any DurabilityChainReading,
        registrar: EntryRegistrar,
        watcher: SubmissionWatcher,
        pass: RecoveryPass,
        trigger: FinalizedHeadTrigger,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.chain = chain
        self.registrar = registrar
        self.watcher = watcher
        self.pass = pass
        self.trigger = trigger
        paymentStatusQuery = PaymentStatusQuery(store: store, chain: chain)
        self.logger = logger
    }
}

// MARK: - DurabilityServicing

extension DurabilityService: DurabilityServicing {
    public func submit(
        inputs: [Input],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission {
        // Registration commits and takes ownership before anything is broadcast, so an
        // extrinsic can never exist without an entry describing what it consumes.
        let entry = try await registrar.register(inputs: inputs, outputs: outputs)

        return try await submitRegistered(entryId: entry.id, builder: builder, origin: origin)
    }

    public func submitRegistered(
        entryId: TransactionId,
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission {
        try await watcher.submit(entryId: entryId, builder: builder, origin: origin)
    }

    public func abandon(_ id: TransactionId) {
        registrar.abandon(id)
    }

    public func register(inputs: [Input], outputs: [OwnAsset]) async throws -> TransactionId {
        try await registrar.register(inputs: inputs, outputs: outputs).id
    }

    public func startRecoveryPass() {
        Task { [pass] in
            await pass.run()
        }
    }

    public func start() {
        let task = Task { [pass, trigger] in
            await pass.run()
            await trigger.run()
        }
        let previous = triggerTask.withLock { current in
            let old = current
            current = task
            return old
        }
        previous?.cancel()
    }

    public func stop() {
        let task = triggerTask.withLock { current in
            let old = current
            current = nil
            return old
        }
        task?.cancel()
    }

    public func transactionStatus(_ id: TransactionId) async throws -> EntryStatus {
        guard let entry = try await store.fetch(id: id) else {
            throw DurabilityError.entryNotFound(id)
        }
        return entry.status
    }

    public func registerHandoff(_ coin: OwnAsset) async throws {
        try await store.markHandedOff(coin)
    }

    public func assetStatus(_ asset: OwnAsset) async throws -> CoinageAssetState {
        try await assetStatuses([asset])[asset]
            ?? CoinageAssetState(lock: .idle, minterStatus: nil)
    }

    /// Derived from the live entry set rather than stored, so it cannot drift from it.
    public func assetStatuses(_ assets: [OwnAsset]) async throws -> [OwnAsset: CoinageAssetState] {
        guard !assets.isEmpty else { return [:] }

        let handedOff = try await store.handedOffIdentifiers()
        let reservedInputs = try await store.fetchLive().inputIdentifiers()
        let mintersByOutput = try await store.fetchAll().mintersByOutputIdentifier()

        return assets.reduce(into: [:]) { result, asset in
            let identifier = asset.identifier
            let lock: AssetStatus =
                if handedOff.contains(identifier) {
                    .handedOff
                } else if reservedInputs.contains(identifier) {
                    .reserved
                } else {
                    .idle
                }
            result[asset] = CoinageAssetState(
                lock: lock,
                minterStatus: mintersByOutput[identifier]?.status
            )
        }
    }

    public func paymentStatus(of coin: OwnAsset) async throws -> CoinPaymentStatus {
        let view = try await chain.pinChainView()
        return try await paymentStatusQuery.status(of: coin, view: view)
    }
}
