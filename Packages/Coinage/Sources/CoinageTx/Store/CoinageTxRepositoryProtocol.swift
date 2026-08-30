import AsyncExtensions
import Foundation

/// Persistence for durability entries and handoff marks — the single seam that folds the former
/// `DurabilityStoring` + `CoinageTransacting` store abstraction into one repository. Mirrors
/// Android's `CoinageEntryRepository`.
///
/// Entries are never deleted; terminal rows stay as history because `minter(of:)` and
/// `consumers(of:)` must still see them.
///
/// Handoff marks are a separate insert-only record: `hasEverBeenHandedOff` asks whether an asset
/// has *ever* carried a mark, so the fact has to survive any later state change.
public protocol CoinageTxRepositoryProtocol: Sendable {
    /// Mints a ``CoinageTxId``, inserts an entry built from `registration`, and hands the id to
    /// `onCommit` — all inside one transaction, after `validation`, so nothing can move what it
    /// checked and a caller can take ownership before any other reader sees the row. A throw from
    /// `validation` leaves nothing behind. Assigns the monotonic `sequence`. Mirrors Android's
    /// `registerValidated`.
    func register(
        _ registration: CoinageTxRegistration,
        validation: @escaping (any CoinageTxValidationContext) throws -> Void,
        onCommit: @escaping (CoinageTxId) -> Void
    ) async throws

    /// The same for several registrations that are one operation: all commit or none do. `validation`
    /// runs once against the whole batch (it must reject within-batch conflicts itself, since the rows
    /// do not exist yet). `onCommit` receives the minted ids in registration order. Mirrors Android's
    /// batch `registerAllValidated`.
    func registerAll(
        _ registrations: [CoinageTxRegistration],
        validation: @escaping (any CoinageTxValidationContext) throws -> Void,
        onCommit: @escaping ([CoinageTxId]) -> Void
    ) async throws

    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws

    /// Atomically applies `verdict` iff the entry's current status still equals
    /// `expectedCurrentStatus` and is not terminal — the read and the write share one transaction,
    /// so the status cannot move between them. Returns whether it wrote. The single guarded writer
    /// of a rule verdict; mirrors Android's `compareAndSetStatus`.
    @discardableResult
    func updateTxStatus(
        for id: CoinageTxId,
        expectedCurrentStatus: CoinageTxStatus,
        verdict: Verdict
    ) async throws -> Bool

    /// Every entry, live and terminal, ordered by `sequence`. Mirrors Android's `getAllEntries`.
    func getAllEntries() async throws -> [CoinageTxEntry]

    /// The entry with this id, if any. Mirrors Android's `getEntry`.
    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry?

    /// A stream of an entry's status: the current value, then every change. For a caller that must
    /// await a terminal outcome (offboarding an external payment) rather than fire-and-forget.
    func subscribeStatus(id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus>

    /// The entry that minted this asset, if any.
    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry?

    /// Every entry consuming this input, including terminal ones.
    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry]

    /// Provisionally marks assets handed off (`.pending`) after running `validation` in the same
    /// transaction — so nothing can claim them between the check and the mark, and a throw rolls the
    /// whole thing back. Released on relaunch unless committed. Mirrors Android's `markHandedOff`.
    func precommitHandOff(
        _ assets: [OwnAsset],
        validation: @escaping (any CoinageTxValidationContext) throws -> Void
    ) async throws

    /// Promotes provisional marks to final (`.committed`) — the keys have durably left. Keyed by
    /// ``OwnAsset/publicKey``, the form the transport can name without reconstructing the asset.
    /// Mirrors Android's `commitHandoffs`.
    func commitHandoffs(_ keys: [PublicKey]) async throws

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

    /// The entry's current status, if it exists. Mirrors Android's `getStatus`.
    func getStatus(_ id: CoinageTxId) async throws -> CoinageTxStatus? {
        try await getEntry(id: id)?.status
    }
}
