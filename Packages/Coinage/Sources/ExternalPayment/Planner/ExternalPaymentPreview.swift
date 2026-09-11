import BigInt
import Foundation

/// The result of external payment planning, doubling as a preview before execution.
public enum ExternalPaymentPreview {
    /// Enough spendable vouchers to cover the amount.
    case ready(Selection)

    /// Not enough spendable vouchers, but spendable coins cover the deficit once recycled.
    case loadCoins(Selection)

    /// Permanent failure — what is spendable on-chain cannot cover the amount.
    case notEnoughBalance
}

// MARK: - Selection

public extension ExternalPaymentPreview {
    /// Pre-computed selection of vouchers/coins.
    struct Selection {
        /// Vouchers selected for this payment (offboarding candidates for `.ready`; the exact
        /// vouchers that must join the recycled ones for `.loadCoins`).
        public let vouchers: [Voucher]
        /// Coins selected for recycling (empty for `.ready`).
        public let coins: [Coin]
        /// The originally requested transfer amount.
        public let fullAmount: BigUInt

        public init(vouchers: [Voucher], coins: [Coin], fullAmount: BigUInt) {
            self.vouchers = vouchers
            self.coins = coins
            self.fullAmount = fullAmount
        }
    }
}

// MARK: - Convenience

public extension ExternalPaymentPreview {
    var selection: Selection? {
        switch self {
        case let .ready(selection),
             let .loadCoins(selection):
            selection
        case .notEnoughBalance:
            nil
        }
    }

    var fullAmount: BigUInt { selection?.fullAmount ?? .zero }

    var isExecutable: Bool {
        switch self {
        case .ready,
             .loadCoins:
            true
        case .notEnoughBalance:
            false
        }
    }
}
