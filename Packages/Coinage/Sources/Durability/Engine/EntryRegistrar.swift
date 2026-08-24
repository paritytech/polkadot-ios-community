import Foundation
import SDKLogger

/// Creates entries and hands them to a submission.
///
/// The store enforces the four registration invariants in one call — non-empty entry, fresh
/// outputs, unique consumer, blocked handoff — so a rejected registration leaves nothing
/// behind.
public struct EntryRegistrar {
    private let store: any DurabilityStoring
    private let chain: any DurabilityChainReading
    private let watched: WatchedEntrySet
    private let mortality: UInt32
    private let logger: SDKLoggerProtocol?

    public init(
        store: any DurabilityStoring,
        chain: any DurabilityChainReading,
        watched: WatchedEntrySet,
        mortality: UInt32,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.chain = chain
        self.watched = watched
        self.mortality = mortality
        self.logger = logger
    }

    /// Registers an entry and takes submission ownership of it.
    ///
    /// The caller submits only after this returns; a throw means nothing was registered and
    /// nothing is owned.
    public func register(inputs: [Input], outputs: [OwnAsset]) async throws -> DurabilityEntry {
        guard !inputs.isEmpty || !outputs.isEmpty else {
            throw DurabilityError.emptyEntry
        }

        // The checkpoint is the finalized head read once before registration. Rule 7's search
        // window starts here, so the extrinsic cannot appear below it. No input is read from
        // chain during registration.
        let checkpoint = try await chain.pinChainView().finalized

        let entry = DurabilityEntry(
            inputs: inputs,
            outputs: outputs,
            checkpoint: checkpoint,
            mortality: mortality
        )

        // Ownership is taken before the row exists rather than after, so a pass can never see
        // an unowned row. It errs the safe way — a pass can only ever skip an entry it should
        // have skipped.
        watched.take(entry.id)

        do {
            try await store.register(entry)
        } catch {
            watched.release(entry.id)
            throw error
        }

        logger?.debug("Registered entry \(entry.id): \(inputs.count) in, \(outputs.count) out")
        return entry
    }

    /// Releases ownership of an entry that was registered but will never be submitted.
    ///
    /// Ownership is taken at registration so a pass cannot judge an entry mid-flight. A caller
    /// that registers and then fails before submitting must hand ownership back, or the pass
    /// skips the entry forever and its inputs never return. One-shot, like every other release:
    /// `WatchedEntrySet.release` reports whether it did anything.
    public func abandon(_ id: TransactionId) {
        watched.release(id)
    }
}
