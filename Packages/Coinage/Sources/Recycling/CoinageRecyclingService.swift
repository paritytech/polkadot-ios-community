import Foundation
import ExtrinsicService
import KeyDerivation
import Keystore_iOS
import Operation_iOS
import SDKLogger
import SubstrateSdk
import StructuredConcurrency

/// Persisted recycling intent handed from `prepareRecycle` to the submission step.
private struct PreparedRecycle {
    let voucher: Voucher
    let origin: any ExtrinsicOriginDefining
    let builder: ExtrinsicBuilderClosure
}

/// Submits coin recycling. The decision of *which* coins to recycle lives in `CoinRecyclingEvaluator`;
/// this service only submits, fire-and-forget, one `loadRecyclerWithCoin` extrinsic per coin. The
/// durability layer resolves each outcome; a coin whose extrinsic never lands is released by the
/// recovery pass at mortality, so there is nothing to roll back here.
actor CoinageRecyclingService {
    private let voucherMinter: any VoucherMinting
    private let coinKeypairFactory: any CoinKeyDeriving
    private let voucherKeypairFactory: any VoucherKeyDeriving
    private let txService: any CoinageTxServicing
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol

    init(
        voucherMinter: any VoucherMinting,
        coinKeypairFactory: any CoinKeyDeriving,
        voucherKeypairFactory: any VoucherKeyDeriving,
        txService: any CoinageTxServicing,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol
    ) {
        self.voucherMinter = voucherMinter
        self.coinKeypairFactory = coinKeypairFactory
        self.voucherKeypairFactory = voucherKeypairFactory
        self.txService = txService
        self.originFactory = originFactory
        self.logger = logger
    }
}

// MARK: - CoinageRecyclingServicing

extension CoinageRecyclingService: CoinageRecyclingServicing {
    func recycleCoins(_ coins: [Coin]) async throws {
        for coin in coins {
            try await recycleCoin(coin)
        }
    }
}

// MARK: - Private

private extension CoinageRecyclingService {
    /// Fire-and-forget recycle of a single coin, matching Appendix B's `load_recycler_with_coin`:
    /// `prepareRecycle` mints the voucher, then `submit` registers the entry — which claims the coin —
    /// and tracks the extrinsic in the background.
    func recycleCoin(_ coin: Coin) async throws {
        let prepared = try await prepareRecycle(coin)
        try await txService.submitTransaction(
            request: CoinageTxRequest(
                inputs: [.coin(.own(coin.derivationIndex, coin.publicKey))],
                outputs: [.recyclerVoucher(prepared.voucher.derivationIndex, prepared.voucher.publicKey)],
                builder: prepared.builder,
                origin: prepared.origin
            ),
            groupId: nil
        )
        logger.debug("Submitted recycle: coin \(coin.derivationIndex) -> voucher \(prepared.voucher.derivationIndex)")
    }

    /// Locks the coin, allocates the voucher, and persists the voucher (`.pendingOnboarding`)
    /// before submission so a crash mid-flight is recoverable. Throws before anything is broadcast.
    func prepareRecycle(_ coin: Coin) async throws -> PreparedRecycle {
        // The coin is reserved by its `load_recycler` durability entry at submission — a live
        // input derives to `.pendingTransfer` — so no separate pre-lock is written here.
        let voucher = try await voucherMinter.mintVoucher(exponent: coin.exponent)

        let memberKey = voucher.publicKey
        let keyManager = try voucherKeypairFactory.createKeyManager(for: voucher)
        let coinPublicKey = coin.publicKey
        let proof = try keyManager.sign(coinPublicKey)

        let call = CoinagePallet.Calls.LoadRecyclerWithCoin(
            memberKey: memberKey,
            proofOfOwnership: proof
        )
        let coinWallet = try CoinDerivedWallet(
            privateKey: coinKeypairFactory.derivePrivateKey(for: coin),
            publicKey: coinPublicKey
        )
        let origin = try originFactory.createAsCoinOrigin(for: coinWallet)
        let builder: ExtrinsicBuilderClosure = { try $0.adding(call: call.callAsFunction()) }

        // The voucher is already persisted by the allocator, so a crash mid-flight is recoverable.
        return PreparedRecycle(voucher: voucher, origin: origin, builder: builder)
    }
}
