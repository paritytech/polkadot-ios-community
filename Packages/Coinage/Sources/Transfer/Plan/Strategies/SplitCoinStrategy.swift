import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt
import SDKLogger

/// Strategy 2: split one coin into recipient and change denominations.
///
/// Only `overflowCoin` is consumed on chain, so it is the entry's single input — which is what
/// Appendix B says a split takes. `wholeCoins` are passed to the recipient untouched and are
/// recorded as handoffs rather than as inputs.
///
/// Both the recipient coins and the change coins are declared as outputs. Recording the
/// recipient side matters: an entry that declares only its change has no evidence left once
/// the peer claims, and cannot be told apart from one that never executed.
struct SplitCoinStrategy {
    private let wholeCoins: [Coin]
    private let overflowCoin: Coin
    private let recipientCoins: [Coin]
    private let changeCoins: [Coin]
    private let coinKeyFactory: any CoinKeyDeriving
    private let durability: any DurabilityServicing
    private let originFactory: OriginCreating
    private let logger: SDKLoggerProtocol?

    init(
        wholeCoins: [Coin],
        overflowCoin: Coin,
        recipientCoins: [Coin],
        changeCoins: [Coin],
        coinKeyFactory: any CoinKeyDeriving,
        durability: any DurabilityServicing,
        originFactory: OriginCreating,
        logger: SDKLoggerProtocol?
    ) {
        self.wholeCoins = wholeCoins
        self.overflowCoin = overflowCoin
        self.recipientCoins = recipientCoins
        self.changeCoins = changeCoins
        self.coinKeyFactory = coinKeyFactory
        self.durability = durability
        self.originFactory = originFactory
        self.logger = logger
    }
}

// MARK: - TransferStrategy

extension SplitCoinStrategy: TransferStrategy {
    func run(context: TransferContext) async throws {
        try await submitSplit(context: context)
    }
}

// MARK: - Private

private extension SplitCoinStrategy {
    func submitSplit(context: TransferContext) async throws {
        let allNewCoins = recipientCoins + changeCoins
        let splitDestinations = try buildSplitDestinations(from: allNewCoins)

        let call = CoinagePallet.Calls.Split(
            splitInto: splitDestinations.sorted { $0.exponent < $1.exponent }
        )
        let builder: ExtrinsicBuilderClosure = {
            try $0.adding(call: call.callAsFunction())
        }
        let origin = try makeOrigin()

        // Registration first: the projection writes below are only an anticipation of what the
        // reconciler will compute, and it can only agree once the entry exists.
        let entryId = try await durability.register(
            inputs: [.coin(.own(overflowCoin.derivationIndex))],
            outputs: allNewCoins.map { .coin($0.derivationIndex) }
        )

        do {
            try await context.reserve(coins: wholeCoins + [overflowCoin], vouchers: [])
            try await context.handOff(coins: wholeCoins)
            try await context.insertOutputs(coins: allNewCoins)
        } catch {
            durability.abandon(entryId)
            throw error
        }

        logger?.debug("Submitting split extrinsic for \(allNewCoins.count) coins")

        let result = try await durability.submitRegistered(
            entryId: entryId,
            builder: builder,
            origin: origin
        )

        switch result.submission.status {
        case .success:
            logger?.debug("Split extrinsic succeeded")
            try await context.handOff(coins: recipientCoins)
            await context.settle()
        case let .failure(error):
            logger?.error("Split extrinsic failed: \(error.error)")
            await context.settle()
            throw TransferStrategyError.submissionFailed(error.error)
        }
    }

    func buildSplitDestinations(
        from coins: [Coin]
    ) throws -> [CoinagePallet.Calls.Split.SplitDestination] {
        var grouped: [Int16: [Data]] = [:]
        for coin in coins {
            let accountId = try coinKeyFactory.derivePublicKey(for: coin)
            grouped[coin.exponent, default: []].append(accountId)
        }

        return grouped.map { exponent, accounts in
            CoinagePallet.Calls.Split.SplitDestination(
                exponent: exponent,
                accounts: accounts
            )
        }
    }

    func makeOrigin() throws -> ExtrinsicOriginDefining {
        let coinAccount = try CoinDerivedWallet(
            privateKey: coinKeyFactory.derivePrivateKey(for: overflowCoin),
            publicKey: coinKeyFactory.derivePublicKey(for: overflowCoin)
        )

        return try originFactory.createAsCoinOrigin(for: coinAccount)
    }
}
