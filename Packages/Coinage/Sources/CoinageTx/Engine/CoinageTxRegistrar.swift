import Foundation
import SDKLogger

/// Creates entries and hands them to a submission.
///
/// The store enforces the four registration invariants in one call — non-empty entry, fresh
/// outputs, unique consumer, blocked handoff — so a rejected registration leaves nothing
/// behind.
public struct CoinageTxRegistrar {
    private let store: any CoinageTxRepositoryProtocol
    private let validator: CoinageTxRegistrationValidator
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let watched: CoinageTrackingTxSet
    private let mortality: UInt32
    private let logger: SDKLoggerProtocol?

    public init(
        store: any CoinageTxRepositoryProtocol,
        validator: CoinageTxRegistrationValidator,
        chainFactory: any CoinageChainViewFactoryProtocol,
        watched: CoinageTrackingTxSet,
        mortality: UInt32,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.validator = validator
        self.chainFactory = chainFactory
        self.watched = watched
        self.mortality = mortality
        self.logger = logger
    }

    /// Registers an entry and takes submission ownership of it.
    ///
    /// The caller submits only after this returns; a throw means nothing was registered and
    /// nothing is owned.
    public func register(
        inputs: [CoinageTxInput],
        outputs: [OwnAsset],
        groupId: CoinageTxGroupId? = nil
    ) async throws -> CoinageTxEntry {
        guard !inputs.isEmpty || !outputs.isEmpty else {
            throw CoinageTxError.emptyEntry
        }

        // The checkpoint is the finalized head read once before registration. Rule 7's search
        // window starts here, so the extrinsic cannot appear below it. No input is read from
        // chain during registration.
        let checkpoint = try await chainFactory.pin().finalizedHead

        let entry = CoinageTxEntry(
            inputs: inputs,
            outputs: outputs,
            groupId: groupId,
            checkpoint: checkpoint,
            mortality: mortality
        )

        // Ownership is taken before the row exists rather than after, so a pass can never see
        // an unowned row. It errs the safe way — a pass can only ever skip an entry it should
        // have skipped.
        watched.take(entry.id)

        do {
            try await store.register(entry) { [validator] context in
                try validator.validate(entry, transaction: context)
            }
        } catch {
            watched.release(entry.id)
            throw error
        }

        logger?.debug("Registered entry \(entry.id): \(inputs.count) in, \(outputs.count) out")
        return entry
    }

    /// Registers several entries atomically under one `groupId` and takes ownership of each.
    ///
    /// All share one pinned checkpoint. The store validates and inserts them in one transaction,
    /// so a within-batch conflict rejects the whole batch and nothing is owned. The returned ids
    /// are in request order, so a caller can pair each with the request that produced it.
    public func registerAll(
        requests: [CoinageTxRequest],
        groupId: CoinageTxGroupId?
    ) async throws -> [CoinageTxId] {
        guard !requests.isEmpty else { return [] }
        guard requests.allSatisfy({ !$0.inputs.isEmpty || !$0.outputs.isEmpty }) else {
            throw CoinageTxError.emptyEntry
        }

        let checkpoint = try await chainFactory.pin().finalizedHead

        let entries = requests.map { request in
            CoinageTxEntry(
                inputs: request.inputs,
                outputs: request.outputs,
                groupId: groupId,
                checkpoint: checkpoint,
                mortality: mortality
            )
        }

        for entry in entries {
            watched.take(entry.id)
        }

        do {
            try await store.registerAll(entries) { [validator] entry, context in
                try validator.validate(entry, transaction: context)
            }
        } catch {
            for entry in entries {
                watched.release(entry.id)
            }
            throw error
        }

        logger?.debug("Registered \(entries.count) entries under group \(groupId)")
        return entries.map(\.id)
    }

    /// Releases ownership of an entry that was registered but will never be submitted.
    ///
    /// Ownership is taken at registration so a pass cannot judge an entry mid-flight. A caller
    /// that registers and then fails before submitting must hand ownership back, or the pass
    /// skips the entry forever and its inputs never return. One-shot, like every other release:
    /// `CoinageTrackingTxSet.release` reports whether it did anything.
    public func abandon(_ id: CoinageTxId) {
        watched.release(id)
    }
}
