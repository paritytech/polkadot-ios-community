import AsyncExtensions
import Foundation
import ExtrinsicService
import SDKLogger
import os

/// The durability subsystem's public face.
public protocol DurabilityServicing: Sendable {
    /// Registers an entry and starts tracking its extrinsic in the background, returning the entry's
    /// id as soon as it is committed — so the inputs are claimed before this returns, but the caller
    /// does not wait for inclusion. Status is resolved by the tracker and the recovery pass, and a
    /// caller that must await the outcome observes it via ``subscribeTransactionStatus(_:)``.
    @discardableResult
    func submit(
        inputs: [DurabilityInput],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> TransactionId

    /// A stream of a submitted entry's status: the current value, then every change. Lets a caller
    /// that must not report success until the chain has — offboarding an external payment — await a
    /// terminal outcome after a fire-and-forget ``submit(inputs:outputs:builder:origin:)``.
    func subscribeTransactionStatus(_ id: TransactionId) -> AnyAsyncSequence<EntryStatus>

    /// Starts a recovery pass without waiting for it. Never awaited by startup: a single
    /// unresolvable entry must not hold the app for a mortality window.
    func startRecoveryPass()

    /// Starts the finalized-head trigger and runs one pass immediately.
    ///
    /// Subsumes ``startRecoveryPass()``: callers that only need the one-shot pass keep using that.
    func start()

    /// Cancels the finalized-head trigger. Safe to call when not started.
    func stop()

    /// Provisionally reserves `assets` against being spent again, before their keys reach the
    /// transport. The reservation is released on relaunch unless the returned handle is committed
    /// once the carrying payload is durable — so a payment that fails after this point never
    /// freezes the coins.
    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit

    /// Clears the reservations of payments that never became durable. Runs once, on launch.
    func releaseUncommittedHandoffs() async throws
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
    private let registrar: EntryRegistrar
    private let watcher: SubmissionWatcher
    private let pass: RecoveryPass
    private let trigger: FinalizedHeadTrigger
    private let logger: SDKLoggerProtocol?

    private let triggerTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(
        store: any DurabilityStoring,
        registrar: EntryRegistrar,
        watcher: SubmissionWatcher,
        pass: RecoveryPass,
        trigger: FinalizedHeadTrigger,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.registrar = registrar
        self.watcher = watcher
        self.pass = pass
        self.trigger = trigger
        self.logger = logger
    }
}

// MARK: - DurabilityServicing

extension DurabilityService: DurabilityServicing {
    @discardableResult
    public func submit(
        inputs: [DurabilityInput],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> TransactionId {
        // Registration commits and takes ownership before anything is broadcast, so an extrinsic
        // can never exist without an entry describing what it consumes. Tracking then runs in the
        // background: the caller does not wait for inclusion. A submission that never resolves is
        // finished by the recovery pass at mortality.
        let entry = try await registrar.register(inputs: inputs, outputs: outputs)

        watcher.watch(entryId: entry.id, builder: builder, origin: origin)

        return entry.id
    }

    public func subscribeTransactionStatus(_ id: TransactionId) -> AnyAsyncSequence<EntryStatus> {
        store.subscribeStatus(of: id)
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

    public func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        try await store.markHandoffPending(assets)
        return StoreHandoffCommit(assets: assets, store: store)
    }

    public func releaseUncommittedHandoffs() async throws {
        try await store.releaseUncommittedHandoffs()
    }
}
