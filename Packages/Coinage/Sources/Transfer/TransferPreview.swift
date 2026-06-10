import Foundation
import BigInt

/// Holds a pre-computed coin selection result along with both the full and non-degraded
/// sendable amounts so the caller can present a privacy warning before executing.
public struct TransferPreview {
    public let selectionResult: CoinSelectionResult
    /// The originally requested transfer amount (all coins + all vouchers).
    public let fullAmount: BigUInt
    /// Amount achievable using only full-privacy vouchers (coins + full-only allocations).
    public let nonDegradedAmount: BigUInt

    public var isDegraded: Bool { selectionResult.privacyLevel == .degraded }

    /// A copy of `selectionResult` with degraded voucher groups stripped out.
    /// For `.exactMatch` and `.split` this is identical to `selectionResult`.
    public var nonDegradedResult: CoinSelectionResult {
        switch selectionResult {
        case .exactMatch,
             .split:
            return selectionResult
        case let .unloadIntoCoins(coins, perGroupAllocations):
            let fullAllocations = perGroupAllocations.filter {
                $0.vouchers.allSatisfy { $0.effectivePrivacy() == .full }
            }
            return fullAllocations.isEmpty
                ? .exactMatch(coins: coins)
                : .unloadIntoCoins(coins: coins, perGroupAllocations: fullAllocations)
        }
    }
}
