import Foundation
import Operation_iOS
import SubstrateSdk

public struct Coin: Equatable, CoinageDerivable, Sendable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: DerivationIndex
    public let age: Int16? // nil = unknown, 0 = fresh from unload/split

    /// Local status, derived from the durability entry graph at fetch time — not stored. Set by
    /// `CoinMapper.transform` from the coin's input/output entries, its handoff mark and `isOnchain`.
    public var state: State = .available

    /// On-chain presence, written only by chain sync. The one fact the durability graph cannot
    /// show: a coin `age != nil ∧ ¬isOnchain` was seen on chain and has since vanished — a peer
    /// claimed a handed-off or received coin, leaving no local entry — so it is spent.
    public var isOnchain: Bool = false

    public enum State: Equatable, Sendable {
        case spent
        case available
        /// Reserved by a live entry — a transfer or a recycling; the distinction is not tracked.
        case pendingTransfer
        /// Output of a PENDING entry: this wallet expects to mint it, but the extrinsic has not
        /// resolved. Counted as locked value in the *pending* bucket so an in-flight operation's
        /// output shows exactly once — its inputs are simultaneously counted nowhere.
        case pendingMint
        /// Given to a peer. Terminal locally: a handed-off coin can never re-enter an entry,
        /// and its payment status is derived on demand rather than stored.
        case handedOff
    }

    public init(
        exponent: Int16,
        derivationIndex: DerivationIndex,
        age: Int16?,
        state: State = .available,
        isOnchain: Bool = false
    ) {
        self.exponent = exponent
        self.derivationIndex = derivationIndex
        self.age = age
        self.state = state
        self.isOnchain = isOnchain
    }

    public func changing(state: State) -> Coin {
        Coin(exponent: exponent, derivationIndex: derivationIndex, age: age, state: state, isOnchain: isOnchain)
    }

    public func changing(age: Int16) -> Coin {
        Coin(exponent: exponent, derivationIndex: derivationIndex, age: age, state: state, isOnchain: isOnchain)
    }

    public func changing(isOnchain: Bool) -> Coin {
        Coin(exponent: exponent, derivationIndex: derivationIndex, age: age, state: state, isOnchain: isOnchain)
    }
}

extension Coin: Operation_iOS.Identifiable {
    public var identifier: String {
        Self.identifier(for: derivationIndex)
    }
}

public extension Coin {
    /// The storage identifier for a coin at `derivationIndex`. Single source of truth so no
    /// call site hand-writes the string form.
    static func identifier(for derivationIndex: DerivationIndex) -> String {
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
