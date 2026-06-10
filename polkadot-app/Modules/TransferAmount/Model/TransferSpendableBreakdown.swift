import Foundation
import BigInt

struct TransferSpendableBreakdown: Equatable {
    let secured: BigUInt
    let lowPrivacy: BigUInt
}
