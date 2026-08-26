import Foundation

/// Value stored in `CDCoin.handoffMark`. Insert-only and monotonic — once a coin is handed off it
/// never returns to `.none`, so any non-`.none` value means the coin is handed off.
enum CoinHandoffMark: Int16 {
    case none = 0
    /// Written before the keys leave the device, ahead of statement-store submission.
    case pending = 1
    /// The carrying message has been committed to the statement store.
    case committed = 2
}
