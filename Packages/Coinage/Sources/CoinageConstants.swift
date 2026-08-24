import Foundation

public enum CoinageConstants {
    /// Interval at which the background recycling task is scheduled (24 hours).
    public static let backgroundRecyclingInterval: TimeInterval = 24 * 60 * 60

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

    /// Blocks an entry's extrinsic can still be included for (≈ 5 minutes at 6s blocks).
    static let walMortality: UInt32 = 300

    /// Extra blocks added to the stored mortality before `windowClosed` may fire.
    ///
    /// The real era anchor lives inside `ExtrinsicOperationFactory` and is not surfaced through
    /// `ExtrinsicMonitorSubmission`, so an entry's stored mortality cannot be tied to its
    /// checkpoint. The slack makes the error one-directional: `windowClosed` can only fire
    /// later than the true expiry, never earlier. Firing late freezes inputs for a while;
    /// firing early writes a false FAILURE onto a live extrinsic.
    static let walMortalitySlack: UInt32 = 60

    /// Mortality stored on a new entry.
    static let entryMortality: UInt32 = walMortality + walMortalitySlack
}
