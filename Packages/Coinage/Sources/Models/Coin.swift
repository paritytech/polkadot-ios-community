import Foundation
import Operation_iOS
import SubstrateSdk

public struct Coin: Equatable, CoinageDerivable, Sendable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: DerivationIndex

    /// On-chain age. `nil` means the coin was never seen on chain; `0` is fresh from unload/split.
    public let age: Int16?

    /// On-chain presence, written only by chain sync. Combined with `age`, `age != nil ∧ ¬isOnchain`
    /// means the coin was seen on chain and has since vanished.
    public var isOnchain: Bool = false

    /// Whether the coin has been handed off to a peer, and how far along.
    public var handoffMark: CoinHandoffMark = .none

    public init(
        exponent: Int16,
        derivationIndex: DerivationIndex,
        age: Int16?,
        isOnchain: Bool = false,
        handoffMark: CoinHandoffMark = .none
    ) {
        self.exponent = exponent
        self.derivationIndex = derivationIndex
        self.age = age
        self.isOnchain = isOnchain
        self.handoffMark = handoffMark
    }

    public func changing(age: Int16) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: age,
            isOnchain: isOnchain,
            handoffMark: handoffMark
        )
    }

    public func changing(isOnchain: Bool) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: age,
            isOnchain: isOnchain,
            handoffMark: handoffMark
        )
    }

    public func changing(handoffMark: CoinHandoffMark) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: age,
            isOnchain: isOnchain,
            handoffMark: handoffMark
        )
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
    
    var hasEverBeenOnChain: Bool {
        age != nil
    }

    /// Coins past `coinMaxAge` are due for imminent recycling and must not be
    /// picked for new transfers — the chain may invalidate them before inclusion.
    var isAgeValidToSpend: Bool {
        guard let age else { return false }
        return age < CoinageConstants.recycleAtAge
    }
}
