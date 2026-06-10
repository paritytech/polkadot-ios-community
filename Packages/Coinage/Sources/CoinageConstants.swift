import Foundation

public enum CoinageConstants {
    /// Default interval between recycling runs (24 hours).
    public static let recyclingInterval: TimeInterval = 24 * 60 * 60

    /// Coin age threshold at which coin is still operatable
    public static let coinMaxAge: Int16 = 16

    /// Coin age threshold at which recycling is triggered (coinMaxAge - 2).
    public static let recycleAtAge: Int16 = coinMaxAge - 2

    /// Minimum ring size threshold for full privacy (spec requirement).
    static let minimumRingSize: UInt32 = 10

    /// Lookback window (in seconds) for unload token period calculation (1 hour).
    static let periodLookbackInterval: UInt64 = 3_600

    /// Maximum random wait time before a voucher becomes ready (6 hours).
    static let maxVoucherWaitTime: TimeInterval = 6 * 60 * 60

    /// Blocks to wait before a WAL entry can be reverted (≈ 5 minutes at 6s blocks).
    static let walMortality: UInt32 = 300
}
