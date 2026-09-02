import AsyncExtensions
import BigInt
import CoreData
import Foundation
import Operation_iOS
import SubstrateSdk
import Testing

@testable import Coinage
@testable import polkadot_app

/// End-to-end propagation: a real ``CoinageTxCoreDataRepository`` and ``CoinageBalanceService`` over an
/// in-memory ``UserDataStorageTestFacade`` (an "in-memory repository"), proving that modifying a
/// coinage tx entry re-emits a changed balance through the `subscribeSnapshot` path.
@Suite("Coinage balance propagation")
struct CoinageBalanceTests {
    private let context = DenominationBreakdownContext(
        unit: BigUInt(1_000_000),
        precision: 6,
        maxExponent: 7,
        minExponent: -6
    )

    @Test("Failing the entry that reserves a coin re-emits it as spendable")
    func entryStatusChangePropagatesToBalance() async throws {
        let facade = UserDataStorageTestFacade()
        let store = CoinageTxCoreDataRepository(storageFacade: facade)
        let factory = CoinageDatabaseDependencyFactory(storageFacade: facade)

        let coinKey = Data(repeating: 1, count: 32)
        try await persistCoin(exponent: 1, index: 0, key: coinKey, facade: facade)

        // An entry consuming the coin: while it is live the coin is reserved (spendable nowhere).
        let entryId = try await registerConsumer(of: coinKey, store: store)

        let service = CoinageBalanceService(
            denominationContext: context,
            databaseFactory: factory,
            logger: nil
        )
        service.start()

        // Baseline: the coin is reserved by the live entry, so it counts nowhere.
        let baseline = try await firstSpendable(from: service) { $0 == 0 }
        #expect(baseline == 0)

        // Failing the entry releases the input; the change must reach the balance stream.
        try await store.updateTxStatus(
            for: entryId,
            expectedCurrentStatus: .pending,
            verdict: Verdict(status: .failure, successDetectedAt: nil)
        )

        let released = try await firstSpendable(from: service) { $0 == context.valueInPlanks(for: 1) }
        #expect(released == context.valueInPlanks(for: 1))

        service.stop()
    }
}

// MARK: - Helpers

private extension CoinageBalanceTests {
    func persistCoin(
        exponent: Int16,
        index: DerivationIndex,
        key: Data,
        facade: UserDataStorageTestFacade
    ) async throws {
        let repo = facade.makeRepo(mapper: CoinMapper())
        let coin = Coin(exponent: exponent, derivationIndex: index, age: 0, isOnchain: true, publicKey: key)
        try await repo.saveOperation({ [coin] }, { [] }).asyncExecute()
    }

    func registerConsumer(of key: Data, store: CoinageTxCoreDataRepository) async throws -> CoinageTxId {
        let registration = CoinageTxRegistration(
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 100, hash: Data([100])),
            mortalityBlocks: 64,
            groupId: nil,
            inputs: [.coin(.own(0, key))],
            outputs: []
        )
        let validator = CoinageTxRegistrationValidator()
        let captured = CapturedId()
        try await store.register(
            [registration],
            validation: { try validator.validate([registration], transaction: $0) },
            onCommit: { captured.id = $0.first }
        )
        guard let id = captured.id else { throw BalanceTestError.registrationFailed }
        return id
    }

    /// First spendable-total (`fullPrivacy + degraded`) emission matching `predicate`, or a timeout.
    func firstSpendable(
        from service: CoinageBalanceServiceProtocol,
        timeout: Duration = .seconds(120),
        where predicate: @escaping @Sendable (BigUInt) -> Bool
    ) async throws -> BigUInt {
        try await withThrowingTaskGroup(of: BigUInt?.self) { group in
            group.addTask {
                for try await model in service.spendableBalanceStream {
                    let total = model.fullPrivacy.balanceInPlanks() + model.degraded.balanceInPlanks()
                    if predicate(total) { return total }
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let value = first else { throw BalanceTestError.timeout }
            return value
        }
    }
}

private enum BalanceTestError: Error {
    case registrationFailed
    case timeout
}

private final class CapturedId: @unchecked Sendable {
    var id: CoinageTxId?
}
