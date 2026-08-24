import Foundation
import Operation_iOS
import SubstrateSdk

public struct Coin: Equatable, CoinageDerivable, Sendable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: UInt32
    public let age: Int16? // nil = unknown, 0 = fresh from unload/split

    public var state: State = .available

    public enum State: Equatable, Sendable {
        case spent
        case available
        case recycling
        case pendingTransfer
        /// Output of a PENDING entry: this wallet expects to mint it, but the extrinsic has not
        /// resolved. Counted as locked value in the *pending* bucket so an in-flight operation's
        /// output shows exactly once — its inputs are simultaneously counted nowhere.
        case pendingMint
        /// Given to a peer. Terminal locally: a handed-off coin can never re-enter an entry,
        /// and its payment status is derived on demand rather than stored.
        case handedOff

        var isAvailableOrRecycling: Bool {
            self == .available || self == .recycling
        }
    }

    public init(
        exponent: Int16,
        derivationIndex: UInt32,
        age: Int16?,
        state: State = .available
    ) {
        self.exponent = exponent
        self.derivationIndex = derivationIndex
        self.age = age
        self.state = state
    }

    public func changing(state: State) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: age,
            state: state
        )
    }

    public func changing(age: Int16) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: age,
            state: state
        )
    }
}

extension Coin: Operation_iOS.Identifiable {
    public var identifier: String {
        "\(derivationIndex)"
    }
}

public extension Coin {
    /// Coins past `coinMaxAge` are due for imminent recycling and must not be
    /// picked for new transfers — the chain may invalidate them before inclusion.
    var isExpiringSoon: Bool {
        guard let age else { return false }
        return age >= CoinageConstants.recycleAtAge
    }

    /// The spec's `selectable(a) ≡ available(a, B) ∧ ¬reserved(a) ∧ no handoff mark`.
    ///
    /// All three conjuncts are already encoded in the projection: `.available` *is* presence at
    /// the best head, `.pendingTransfer` *is* reserved, `.handedOff` *is* the mark. Outer layers
    /// apply their own extra restrictions (expiry, recycling) on top — the spec calls these
    /// necessary but not sufficient.
    var isSelectable: Bool { state == .available }
}
