import AsyncExtensions
import Foundation

/// Persistence for durability entries and handoff marks.
///
/// Entries are never deleted. `fetchLive` filters by status; terminal rows stay as history
/// because `minter(of:)` and `consumers(of:)` must still see them.
///
/// Handoff marks are a separate insert-only record: `ownCoinInputs` asks whether an asset has
/// *ever* carried a mark, so the fact has to survive any later state change.
public protocol DurabilityStoring: Sendable {
    /// Inserts the entry. Throws ``DurabilityError`` when it violates a registration invariant.
    /// Assigns the monotonic `sequence`.
    func register(_ entry: DurabilityEntry) async throws

    func updateStatus(_ id: TransactionId, to status: EntryStatus) async throws

    /// Atomically applies `verdict` iff the entry's current status still equals `observed` and is
    /// not terminal — the read and the write share one transaction, so the status cannot move
    /// between them. Returns whether it wrote. The single guarded writer of a rule verdict; mirrors
    /// Android's `compareAndSetStatus`.
    @discardableResult
    func compareAndSetStatus(_ id: TransactionId, observed: EntryStatus, verdict: Verdict) async throws -> Bool

    /// Writes the block where execution was observed, or clears it. Not a status change.
    func recordSuccessDetected(_ id: TransactionId, at block: BlockRef?) async throws

    /// Writes the submitted extrinsic hash. Not a status change.
    func recordTxHash(_ id: TransactionId, txHash: Data) async throws

    /// Live entries ordered by `sequence`.
    func fetchLive() async throws -> [DurabilityEntry]

    /// Every entry, live and terminal, ordered by `sequence`.
    func fetchAll() async throws -> [DurabilityEntry]

    func fetch(id: TransactionId) async throws -> DurabilityEntry?

    /// A stream of an entry's status: the current value, then every change. For a caller that must
    /// await a terminal outcome (offboarding an external payment) rather than fire-and-forget.
    func subscribeStatus(of id: TransactionId) -> AnyAsyncSequence<EntryStatus>

    /// The entry that minted this asset, if any.
    func minter(of asset: OwnAsset) async throws -> DurabilityEntry?

    /// Every entry consuming this input, including terminal ones.
    func consumers(of input: DurabilityInput) async throws -> [DurabilityEntry]

    /// Provisionally marks assets handed off (`.pending`) in one transaction, before their keys
    /// reach the transport. Released on relaunch unless committed.
    func markHandoffPending(_ assets: [OwnAsset]) async throws

    /// Promotes provisional marks to final (`.committed`) — the keys have durably left.
    func commitHandoffs(_ assets: [OwnAsset]) async throws

    /// Clears every uncommitted (`.pending`) mark. Runs once, on launch.
    func releaseUncommittedHandoffs() async throws

    func hasEverBeenHandedOff(_ asset: OwnAsset) async throws -> Bool

    func handedOffCoins() async throws -> [OwnAsset]
}

public extension DurabilityStoring {
    /// Handoff marks as a set of ``OwnAsset/identifier``, the form every caller compares against.
    func handedOffIdentifiers() async throws -> Set<String> {
        try await Set(handedOffCoins().map(\.identifier))
    }
}
