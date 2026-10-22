import DurableTransactions
import Foundation
import Testing
@testable import Coinage

/// A reclaim rebuilds from its ledger row into the coin its first attempt recorded, signed by the key of the
/// coin it spends. The rebuild finds that coin in the ledger rather than trusting the payment memo.
@Suite("Reclaim Rebuild")
struct ReclaimRebuildTests {
    private let policyId = CoinageSubmissionParams.reclaimPolicyId
    private let spent = RebuildFixtures.coin(1)
    private let destination = RebuildFixtures.coin(7)

    @Test("terms come from the transfer params")
    func termsAreDecoded() throws {
        let rebuild = makeRebuild(coins: [])

        let terms = try #require(
            rebuild.terms(of: RebuildFixtures.transferParams(inSeconds: 60, retryFailures: true))
        )

        #expect(terms.deadline == RebuildFixtures.now.addingTimeInterval(60))
        #expect(terms.retriesFailures)
    }

    @Test("params that cannot be read have no terms")
    func unreadableParamsHaveNoTerms() {
        #expect(makeRebuild(coins: []).terms(of: Data([0xFF])) == nil)
    }

    @Test("a reclaim resolves into the coin it spends and the coin it mints")
    func resolvesIntoSpentAndMintedCoin() async throws {
        let rebuild = makeRebuild(coins: [spent])
        let transaction = try scheduled()
        let assets = [transaction.id: RebuildFixtures.entry(
            id: transaction.id,
            inputs: [.coin(.reclaimed(spent.derivationIndex, spent.publicKey))],
            outputs: [.coin(destination.derivationIndex, destination.publicKey)]
        )]

        let reclaim = try #require(try await rebuild.resolve([transaction], assets: assets)[transaction.id])

        #expect(reclaim.coin == spent)
        #expect(reclaim.destination == destination.publicKey)
    }

    @Test("a coin the ledger reads back as own resolves like a reclaimed one")
    func ownInputResolves() async throws {
        let rebuild = makeRebuild(coins: [spent])
        let transaction = try scheduled()
        let assets = [transaction.id: RebuildFixtures.entry(
            id: transaction.id,
            inputs: [.coin(.own(spent.derivationIndex, spent.publicKey))],
            outputs: [.coin(destination.derivationIndex, destination.publicKey)]
        )]

        let resolved = try await rebuild.resolve([transaction], assets: assets)

        #expect(resolved[transaction.id]?.destination == destination.publicKey)
    }

    @Test("a row that is not one coin in and one coin out resolves to nothing")
    func unbuildableShapesResolveToNothing() async throws {
        let rebuild = makeRebuild(coins: [spent])
        let transaction = try scheduled()
        let spentInput = CoinageTxInput.coin(.reclaimed(spent.derivationIndex, spent.publicKey))
        let mintedOutput = OwnAsset.coin(destination.derivationIndex, destination.publicKey)
        let shapes: [(inputs: [CoinageTxInput], outputs: [OwnAsset])] = [
            ([], [mintedOutput]),
            ([spentInput, spentInput], [mintedOutput]),
            ([.recyclerVoucher(3, RebuildFixtures.key(3))], [mintedOutput]),
            ([spentInput], []),
            ([spentInput], [mintedOutput, mintedOutput]),
        ]

        for shape in shapes {
            let assets = [transaction.id: RebuildFixtures.entry(
                id: transaction.id,
                inputs: shape.inputs,
                outputs: shape.outputs
            )]

            let resolved = try await rebuild.resolve([transaction], assets: assets)

            #expect(resolved[transaction.id] == nil)
        }
    }

    @Test("a reclaim whose coin is not in the ledger resolves to nothing")
    func missingCoinResolvesToNothing() async throws {
        let rebuild = makeRebuild(coins: [])
        let transaction = try scheduled()
        let assets = [transaction.id: RebuildFixtures.entry(
            id: transaction.id,
            inputs: [.coin(.reclaimed(spent.derivationIndex, spent.publicKey))],
            outputs: [.coin(destination.derivationIndex, destination.publicKey)]
        )]

        let resolved = try await rebuild.resolve([transaction], assets: assets)

        #expect(resolved[transaction.id] == nil)
    }

    @Test("the reclaim is signed with the key derived for the coin it spends")
    func buildSignsWithOwnDerivedKey() async throws {
        let keys = StubCoinKeyFactory()
        let rebuild = makeRebuild(coins: [spent], keys: keys)
        let reclaim = ReclaimRebuild.Reclaim(coin: spent, destination: destination.publicKey)

        _ = try await rebuild.build([reclaim])

        #expect(keys.derivedPrivateKeyIndices == [spent.derivationIndex])
    }

    @Test("a reclaim spends exactly the coin it names")
    func inputsAreTheSpentCoin() {
        let rebuild = makeRebuild(coins: [])
        let reclaim = ReclaimRebuild.Reclaim(coin: spent, destination: destination.publicKey)

        #expect(rebuild.inputs(of: reclaim) == [spent.publicKey])
    }
}

private extension ReclaimRebuildTests {
    func makeRebuild(coins: [Coin], keys: any CoinKeyDeriving = StubCoinKeyFactory()) -> ReclaimRebuild {
        ReclaimRebuild(
            coinService: StubCoinService(coins: RebuildFixtures.tracked(coins)),
            coinQuery: StubCoinOnChainQuery(),
            coinKeyFactory: keys,
            builder: ClaimExtrinsicBuilder(
                originFactory: StubOriginFactory(),
                factory: StubTxFactory(),
                chainId: "test-chain"
            )
        )
    }

    func scheduled() throws -> ScheduledDurableTx {
        try RebuildFixtures.scheduled(
            policyId: policyId,
            params: RebuildFixtures.transferParams(inSeconds: 60)
        )
    }
}
