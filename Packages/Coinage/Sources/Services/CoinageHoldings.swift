import Foundation

/// Every holding the user still owns, classified the way the balance classifies it.
///
/// Emitted from the same computation as ``CoinageBalance``, so a display built from these entries and
/// the balance figures shown beside it cannot disagree: the entry values sum exactly to
/// ``CoinageBalance/total``.
///
/// Coins handed off to a peer are absent — the pre-classifiers admit only free assets.
public struct CoinageHoldings: Equatable, Sendable {
    public struct CoinHolding: Equatable, Sendable {
        public let coin: Coin
        /// Whether the current strategy leaves this coin spendable right now. False for coins the
        /// strategy holds back, coins the chain will no longer accept, and coins still arriving.
        public let isSpendable: Bool

        public init(coin: Coin, isSpendable: Bool) {
            self.coin = coin
            self.isSpendable = isSpendable
        }
    }

    public struct VoucherHolding: Equatable, Sendable {
        public let voucher: Voucher
        /// Whether the current strategy considers it fine to unload this voucher immediately.
        public let isUnloadable: Bool

        public init(voucher: Voucher, isUnloadable: Bool) {
            self.voucher = voucher
            self.isUnloadable = isUnloadable
        }
    }

    public let coins: [CoinHolding]
    public let vouchers: [VoucherHolding]

    public init(coins: [CoinHolding], vouchers: [VoucherHolding]) {
        self.coins = coins
        self.vouchers = vouchers
    }

    public static let empty = CoinageHoldings(coins: [], vouchers: [])
}

extension CoinageHoldings {
    /// Classifies pre-bucketed assets. Kept beside ``CoinageBalanceService/calculateBalance`` and fed
    /// the same inputs so the two stay in step: every asset either bucketing counts appears here
    /// exactly once.
    static func make(
        coinBuckets: CoinBuckets,
        voucherBuckets: VoucherBuckets,
        verdicts: RecyclingVerdicts
    ) -> CoinageHoldings {
        let mintedCoins = coinBuckets.minted.map { tracked in
            CoinHolding(
                coin: tracked.coin,
                isSpendable: verdicts[tracked.coin.derivationIndex] == .allowUse
            )
        }

        // Still arriving: no verdict has been formed, so never spendable.
        let mintingCoins = coinBuckets.minting.map {
            CoinHolding(coin: $0.coin, isSpendable: false)
        }

        let usableVouchers = voucherBuckets.usable.map {
            VoucherHolding(voucher: $0.voucher, isUnloadable: true)
        }

        let waitingVouchers = (voucherBuckets.gainingPrivacy + voucherBuckets.minting).map {
            VoucherHolding(voucher: $0.voucher, isUnloadable: false)
        }

        return CoinageHoldings(
            coins: mintedCoins + mintingCoins,
            vouchers: usableVouchers + waitingVouchers
        )
    }
}
