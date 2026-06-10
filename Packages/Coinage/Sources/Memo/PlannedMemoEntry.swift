import Foundation

/// A planned memo entry describing a coin that will be included in the transfer memo.
/// Created during transfer planning, before coin allocation and key derivation.
struct PlannedMemoEntry: Equatable {
    /// The derivation index of the coin (used to derive the private key for the memo).
    let coinDerivationIndex: UInt32

    /// The denomination exponent (power-of-two value).
    let valueExponent: Int16

    /// How this coin was sourced for the transfer.
    let source: Source

    enum Source: Equatable {
        /// An existing coin in the wallet, transferred as-is.
        /// - Parameter age: The coin's current age.
        case existingCoin(age: Int32)
        /// A newly created coin from splitting a larger coin (age = 0).
        case fromSplit
        /// A newly created coin from unloading vouchers (age = 0).
        case fromUnload
    }
}
