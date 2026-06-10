import Foundation
import Operation_iOS
import SubstrateSdk

public struct Coin: Equatable, CoinageDerivable {
    public let exponent: Int16 // 2^n
    public let derivationIndex: UInt32
    public let age: Int16? // nil = unknown, 0 = fresh from unload/split

    public var state: State = .available

    public enum State: Equatable {
        case spent
        case available
        case recycling
        case pendingTransfer

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
