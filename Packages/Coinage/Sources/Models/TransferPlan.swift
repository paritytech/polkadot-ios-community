import Foundation

/// A complete transfer plan produced by the TransferPlanFactory.
///
/// Contains the execution strategy, planned memo entries for the recipient,
/// and the number of claim tokens required.
struct TransferPlan {
    /// The strategy to execute.
    let strategy: TransferStrategy

    /// Planned memo entries for recipient coins.
    /// Each entry describes a coin that will be included in the transfer memo.
    let plannedMemoEntries: [PlannedMemoEntry]

    /// Number of free unload tokens consumed by this plan.
    /// - exactMatch: 0
    /// - split: 0
    /// - unloadIntoCoins: Number of unloads.
    let claimTokensRequired: Int
}
