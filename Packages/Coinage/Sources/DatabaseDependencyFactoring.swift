import AsyncExtensions
import Operation_iOS

/// Protocol for factories that provide database repositories for Coinage.
/// Implemented in the main app target to bridge CoreData infrastructure to the package.
public protocol DatabaseDependencyFactoring: Sendable {
    func makeCoinRepository() -> AnyDataProviderRepository<Coin>
    func makeTrackedCoinRepository() -> AnyDataProviderRepository<TrackedCoin>
    func makeVoucherRepository() -> AnyDataProviderRepository<Voucher>
    func makeTrackedVoucherRepository() -> AnyDataProviderRepository<TrackedVoucher>
    func makeVoucherLocationRepository() -> AnyDataProviderRepository<Voucher>

    /// A stream of full ``TrackedCoin`` snapshots — the current set, then a fresh snapshot on every
    /// CoreData save. Re-emits when an entry's status change touches a coin's relations, so the
    /// durability overlay stays current without a separate change-merge.
    func makeTrackedCoinSnapshotStream() -> AnyAsyncSequence<[TrackedCoin]>
    /// The voucher analogue of ``makeTrackedCoinSnapshotStream()``.
    func makeTrackedVoucherSnapshotStream() -> AnyAsyncSequence<[TrackedVoucher]>
}
