import Operation_iOS

/// Protocol for factories that provide database repositories for Coinage.
/// Implemented in the main app target to bridge CoreData infrastructure to the package.
public protocol DatabaseDependencyFactoring: Sendable {
    func makeCoinRepository() -> AnyDataProviderRepository<Coin>
    func makeCoinStateRepository() -> AnyDataProviderRepository<Coin>
    func makeVoucherRepository() -> AnyDataProviderRepository<Voucher>
    func makeVoucherLocationRepository() -> AnyDataProviderRepository<Voucher>
    func makeCoinProvider() -> StreamableProvider<Coin>
    func makeVoucherProvider() -> StreamableProvider<Voucher>
}
