import Foundation
import ExtrinsicService
import StructuredConcurrency
import SubstrateSdk
import SubstrateSdkExt
import SDKLogger

/// Strategy 2: Split coin(s) into target and change denominations.
/// - `wholeCoins` are transferred intact to recipient (no blockchain tx needed for these)
/// - `overflowCoin` is split to cover remaining amount + generate change
/// Receives pre-allocated coins from the TransferPlanFactory.
struct SplitCoinStrategy {
    private let wholeCoins: [Coin]
    private let overflowCoin: Coin
    private let recipientCoins: [Coin]
    private let changeCoins: [Coin]
    private let coinKeyFactory: any CoinKeyDeriving
    private let coordinator: any ExtrinsicSubmissionCoordinating
    private let originFactory: OriginCreating
    private let walStore: any TransferWALStoring
    private let mortality: UInt32
    private let logger: SDKLoggerProtocol?

    init(
        wholeCoins: [Coin],
        overflowCoin: Coin,
        recipientCoins: [Coin],
        changeCoins: [Coin],
        coinKeyFactory: any CoinKeyDeriving,
        coordinator: any ExtrinsicSubmissionCoordinating,
        originFactory: OriginCreating,
        walStore: any TransferWALStoring,
        mortality: UInt32,
        logger: SDKLoggerProtocol?
    ) {
        self.wholeCoins = wholeCoins
        self.overflowCoin = overflowCoin
        self.recipientCoins = recipientCoins
        self.changeCoins = changeCoins
        self.coinKeyFactory = coinKeyFactory
        self.coordinator = coordinator
        self.originFactory = originFactory
        self.walStore = walStore
        self.mortality = mortality
        self.logger = logger
    }
}

// MARK: - TransferStrategy

extension SplitCoinStrategy: TransferStrategy {
    func run(context: TransferContext) async throws {
        let allNewCoins = recipientCoins + changeCoins
        let splitDestinations = try buildSplitDestinations(from: allNewCoins)

        let call = CoinagePallet.Calls.Split(
            splitInto: splitDestinations.sorted { $0.exponent < $1.exponent }
        )
        let builder: ExtrinsicBuilderClosure = {
            try $0.adding(call: call.callAsFunction())
        }
        let origin = try makeOrigin()

        let inputCoins = wholeCoins + [overflowCoin]
        let walEntry = TransferWALEntry(
            inputCoinIds: inputCoins.map(\.identifier),
            inputVoucherIds: [],
            expectedCoinIndices: changeCoins.map(\.derivationIndex),
            mortality: mortality
        )
        try await walStore.save(walEntry)

        logger?.debug("Submitting split extrinsic for \(allNewCoins.count) coins")

        let submission = try await coordinator.submit(
            walEntryId: walEntry.id,
            builder: builder,
            origin: origin
        )

        switch submission.status {
        case .success:
            logger?.debug("Split extrinsic succeeded")
            try await context.process(spentCoins: inputCoins, change: changeCoins, destinationCoins: recipientCoins)
            try await walStore.delete(id: walEntry.id)
        case let .failure(error):
            logger?.error("Split extrinsic failed: \(error.error)")
            throw TransferStrategyError.submissionFailed(error.error)
        }
    }
}

// MARK: - Private

private extension SplitCoinStrategy {
    func buildSplitDestinations(from coins: [Coin]) throws -> [CoinagePallet.Calls.Split.SplitDestination] {
        // Group coins by exponent, deriving account ID (public key) for each coin
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
