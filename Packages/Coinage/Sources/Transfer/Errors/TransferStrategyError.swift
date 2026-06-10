import Foundation

/// Errors that can occur during transfer strategy execution.
public enum TransferStrategyError: Error {
    /// No coins provided for exact match strategy
    case emptyCoins
    /// No vouchers provided for unload strategy
    case emptyVouchers
    /// Voucher missing recycler information required for unload
    case missingRecyclerInfo
    /// Extrinsic submission failed
    case submissionFailed(Error)
    /// Index allocation failed
    case allocationFailed(Error)
    /// Failed on fetching correct recycler revision
    case invalidRecyclerRevision
    /// Multiple tasks failed; all errors are collected here
    case multiple([Error])
}
