import AsyncExtensions
import Foundation

/// Persistence for durability entries and handoff marks — the single seam that folds the former
/// `DurabilityStoring` + `CoinageTransacting` store abstraction into one repository. Mirrors
/// Android's `CoinageEntryRepository`.
///
/// Entries are never deleted. `fetchLive` filters by status; terminal rows stay as history
/// because `minter(of:)` and `consumers(of:)` must still see them.
///
/// Handoff marks are a separate insert-only record: `ownCoinInputs` asks whether an asset has
/// *ever* carried a mark, so the fact has to survive any later state change.
public protocol CoinageTxRepositoryProtocol: Sendable {
    /// Inserts the entry after running `validation` inside the same transaction — so nothing can
    /// move what it checked before the write, and a throw leaves nothing behind. Assigns the
    /// monotonic `sequence`. Mirrors Android's `registerValidated`.
    func register(
        _ entry: CoinageTxEntry,
        validation: @escaping (any CoinageTxValidationContext) throws -> Void
    ) async throws

    /// Inserts several entries in one transaction — all commit or none do. Each is validated in
    /// turn against the store *and* the entries already inserted earlier in the same batch, so a
    /// within-batch conflict (two entries minting one output, or claiming one input) rejects and
    /// rolls the whole batch back. Assigns each a monotonic `sequence`. Mirrors Android's batch
    /// `registerValidated`.
    func registerAll(
        _ entries: [CoinageTxEntry],
        validation: @escaping (CoinageTxEntry, any CoinageTxValidationContext) throws -> Void
    ) async throws

    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws

    /// Atomically applies `verdict` iff the entry's current status still equals `observed` and is
    /// not terminal — the read and the write share one transaction, so the status cannot move
    /// between them. Returns whether it wrote. The single guarded writer of a rule verdict; mirrors
    /// Android's `compareAndSetStatus`.
    @discardableResult
    func compareAndSetStatus(_ id: CoinageTxId, observed: CoinageTxStatus, verdict: Verdict) async throws -> Bool

    /// Writes the block where execution was observed, or clears it. Not a status change.
    func recordSuccessDetected(_ id: CoinageTxId, at block: BlockRef?) async throws

    /// Writes the submitted extrinsic hash. Not a status change.
    func recordTxHash(_ id: CoinageTxId, txHash: Data) async throws

    /// Live entries ordered by `sequence`.
    func fetchLive() async throws -> [CoinageTxEntry]

    /// Every entry, live and terminal, ordered by `sequence`.
    func fetchAll() async throws -> [CoinageTxEntry]

    func fetch(id: CoinageTxId) async throws -> CoinageTxEntry?

    /// A stream of an entry's status: the current value, then every change. For a caller that must
    /// await a terminal outcome (offboarding an external payment) rather than fire-and-forget.
    func subscribeStatus(of id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus>

    /// The entry that minted this asset, if any.
    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry?

    /// Every entry consuming this input, including terminal ones.
    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry]

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

public extension CoinageTxRepositoryProtocol {
    /// Handoff marks as a set of ``OwnAsset/publicKey``, the form the DAG and callers compare against.
    /// Mirrors Android's `getHandoffKeys`.
    func getHandoffKeys() async throws -> Set<PublicKey> {
        try await Set(handedOffCoins().map(\.publicKey))
    }
}
