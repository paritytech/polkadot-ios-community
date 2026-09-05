import Foundation
import BigInt

/// Holds a pre-computed coin selection result and the requested amount.
public struct TransferPreview {
    public let selectionResult: CoinSelectionResult
    /// The originally requested transfer amount (all coins + all vouchers).
    public let fullAmount: BigUInt

    public init(selectionResult: CoinSelectionResult, fullAmount: BigUInt) {
        self.selectionResult = selectionResult
        self.fullAmount = fullAmount
    }
}
