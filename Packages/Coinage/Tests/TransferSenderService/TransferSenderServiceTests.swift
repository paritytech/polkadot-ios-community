import Testing
import Foundation
import BigInt
import SubstrateSdk
import Individuality
import Operation_iOS
import ExtrinsicService
import KeyDerivation
import SubstrateOperation

@testable import Coinage

/// End-to-end tests for TransferSenderService using real strategy classes.
///
/// Tests the complete flow: TransferSenderService -> CoinSelector -> TransferPlanFactory -> Strategy -> TransferContext
/// External dependencies (extrinsic submission, key derivation) are mocked at the strategy level.
struct TransferSenderServiceTests {
    let testContext = DenominationBreakdownContext(
        unit: BigUInt(1_000_000),
        precision: 6,
        maxExponent: 7,
        minExponent: -6
    )

    let now = Date()

    let mockCoinService = MockCoinService()
    let mockVoucherService = MockVoucherService()

    // MARK: - ExactMatch Strategy Tests

    @Test("ExactMatch: TransferContext receives correct spentCoins, empty vouchers, empty change")
    func exactMatchContextProcessing() async throws {
        // Given: Coins that exactly match the target ($12 = $8 + $4)
        let coin1 = makeCoin(exponent: 3, derivationIndex: 1) // $8
        let coin2 = makeCoin(exponent: 2, derivationIndex: 2) // $4

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)
        let service = makeTransferSenderService()

        // When
        let result = try await service.previewStrategy(
            amount: planks(Decimal(12)),
            availableCoins: [coin1, coin2],
            availableVouchers: [],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        // Then - Wait for background persistence task
        try await waitForPersistence(expectedSpentCoins: 2)

        #expect(Set(mockCoinService.markedSpentIds) == Set([coin1.identifier, coin2.identifier]))
        #expect(mockCoinService.savedCoins.isEmpty)
        #expect(mockVoucherService.deletedIdentifiers.isEmpty)
    }

    // MARK: - UnloadIntoCoins Strategy Tests

    @Test("Two voucher groups: TransferContext receives correct vouchers deleted and change saved")
    func twoVoucherGroupsContextProcessing() async throws {
        let voucher1 = makeVoucher(exponent: 4, derivationIndex: 1, recyclerIndex: 0) // $16
        let voucher2 = makeVoucher(exponent: 3, derivationIndex: 2, recyclerIndex: 1) // $8
        // Total: $24, need $20, change: $4

        let recyclerLoader = MockRecyclerLoader()
        let key4_0 = RecyclerKey(exponent: 4, index: 0)
        recyclerLoader.states[key4_0] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key4_0] = 1

        let key3_1 = RecyclerKey(exponent: 3, index: 1)
        recyclerLoader.states[key3_1] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key3_1] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(20)),
            availableCoins: [],
            availableVouchers: [voucher1, voucher2],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        // Wait for background persistence task: 2 vouchers deleted, change saved
        try await waitForPersistence(expectedSavedCoins: 1, expectedDeletedVouchers: 2)

        #expect(Set(mockVoucherService.deletedIdentifiers) == Set([voucher1.identifier, voucher2.identifier]))
        #expect(mockCoinService.markedSpentIds.isEmpty)
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(4))
    }

    @Test("Three voucher groups: TransferContext receives all vouchers deleted")
    func threeVoucherGroupsContextProcessing() async throws {
        let voucher1 = makeVoucher(exponent: 5, derivationIndex: 1, recyclerIndex: 0) // $32
        let voucher2 = makeVoucher(exponent: 4, derivationIndex: 2, recyclerIndex: 1) // $16
        let voucher3 = makeVoucher(exponent: 3, derivationIndex: 3, recyclerIndex: 2) // $8
        // Total: $56, need $50, change: $6

        let recyclerLoader = MockRecyclerLoader()
        let key5_0 = RecyclerKey(exponent: 5, index: 0)
        recyclerLoader.states[key5_0] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key5_0] = 1

        let key4_1 = RecyclerKey(exponent: 4, index: 1)
        recyclerLoader.states[key4_1] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key4_1] = 1

        let key3_2 = RecyclerKey(exponent: 3, index: 2)
        recyclerLoader.states[key3_2] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key3_2] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(50)),
            availableCoins: [],
            availableVouchers: [voucher1, voucher2, voucher3],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 1, expectedDeletedVouchers: 3)

        #expect(Set(mockVoucherService.deletedIdentifiers) == Set([
            voucher2.identifier,
            voucher3.identifier,
            voucher1.identifier
        ]))
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(6))
    }

    @Test("Five voucher groups: all groups processed correctly through TransferContext")
    func fiveVoucherGroupsContextProcessing() async throws {
        let voucher1 = makeVoucher(exponent: 5, derivationIndex: 1, recyclerIndex: 0) // $32
        let voucher2 = makeVoucher(exponent: 4, derivationIndex: 2, recyclerIndex: 1) // $16
        let voucher3 = makeVoucher(exponent: 3, derivationIndex: 3, recyclerIndex: 2) // $8
        let voucher4 = makeVoucher(exponent: 2, derivationIndex: 4, recyclerIndex: 3) // $4
        let voucher5 = makeVoucher(exponent: 1, derivationIndex: 5, recyclerIndex: 4) // $2
        // Total: $62, need $61, change: $1

        let recyclerLoader = MockRecyclerLoader()
        let exponents: [Int16] = [5, 4, 3, 2, 1]
        for (idx, exp) in exponents.enumerated() {
            let key = RecyclerKey(exponent: exp, index: UInt32(idx))
            recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
            recyclerLoader.revisions[key] = 1
        }

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(61)),
            availableCoins: [],
            availableVouchers: [voucher1, voucher2, voucher3, voucher4, voucher5],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 1, expectedDeletedVouchers: 5)

        #expect(Set(mockVoucherService.deletedIdentifiers) == Set([
            voucher1.identifier,
            voucher2.identifier,
            voucher3.identifier,
            voucher4.identifier,
            voucher5.identifier
        ]))
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(1))
    }

    @Test("Multiple vouchers same recycler group: combined correctly in TransferContext")
    func multipleVouchersSameGroupContextProcessing() async throws {
        let voucher1 = makeVoucher(exponent: 3, derivationIndex: 1, recyclerIndex: 0) // $8
        let voucher2 = makeVoucher(exponent: 3, derivationIndex: 2, recyclerIndex: 0) // $8, same group
        // Group total: $16, need $10, change: $6

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 3, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(10)),
            availableCoins: [],
            availableVouchers: [voucher1, voucher2],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 1, expectedDeletedVouchers: 2)

        #expect(Set(mockVoucherService.deletedIdentifiers) == Set([voucher1.identifier, voucher2.identifier]))
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(6))
    }

    @Test("Coins and voucher when sufficient: coins and voucher used even if voucher covers amount")
    func voucherOnlyWhenSufficientContextProcessing() async throws {
        let coin1 = makeCoin(exponent: 1, derivationIndex: 1) // $2
        let coin2 = makeCoin(exponent: 1, derivationIndex: 2) // $2
        let voucher = makeVoucher(exponent: 4, derivationIndex: 3, recyclerIndex: 0) // $16
        // Need $12, voucher ($16) alone is sufficient

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 4, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(12)),
            availableCoins: [coin1, coin2],
            availableVouchers: [voucher],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSpentCoins: 2, expectedSavedCoins: 1, expectedDeletedVouchers: 1)

        // Voucher is deleted
        #expect(mockVoucherService.deletedIdentifiers == [voucher.identifier])
        // Coins are spent
        #expect(Set(mockCoinService.markedSpentIds) == Set([coin1.identifier, coin2.identifier]))
        // Change = $20 - $12 = $8
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(8))
    }

    @Test("Change denominations are correctly saved to TransferContext")
    func changeDenominationsContextProcessing() async throws {
        let voucher = makeVoucher(exponent: 4, derivationIndex: 1, recyclerIndex: 0) // $16
        // Need $13, change: $3 = $2 + $1

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 4, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(13)),
            availableCoins: [],
            availableVouchers: [voucher],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 2, expectedDeletedVouchers: 1)

        #expect(mockVoucherService.deletedIdentifiers == [voucher.identifier])
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(3))
        let savedExponents = mockCoinService.savedCoins.map(\.exponent).sorted(by: >)
        #expect(savedExponents == [1, 0])
    }

    @Test("Exact voucher match produces no change saved")
    func exactVoucherMatchNoChangeContext() async throws {
        let voucher = makeVoucher(exponent: 3, derivationIndex: 1, recyclerIndex: 0) // $8

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 3, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(8)),
            availableCoins: [],
            availableVouchers: [voucher],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedDeletedVouchers: 1)

        #expect(mockVoucherService.deletedIdentifiers == [voucher.identifier])
        #expect(mockCoinService.savedCoins.isEmpty)
    }

    @Test("Fractional amounts produce correct change saved")
    func fractionalAmountsChangeContext() async throws {
        let voucher = makeVoucher(exponent: 1, derivationIndex: 1, recyclerIndex: 0) // $2

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 1, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(string: "1.5")!),
            availableCoins: [],
            availableVouchers: [voucher],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 1, expectedDeletedVouchers: 1)

        #expect(mockVoucherService.deletedIdentifiers == [voucher.identifier])
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(string: "0.5"))
    }

    @Test("Larger voucher with change: proper change denominations saved")
    func largerVoucherWithChangeContext() async throws {
        // Use exponent 5 ($32) for a simpler test case
        let voucher = makeVoucher(exponent: 5, derivationIndex: 1, recyclerIndex: 0) // $32

        let recyclerLoader = MockRecyclerLoader()
        let key = RecyclerKey(exponent: 5, index: 0)
        recyclerLoader.states[key] = MembersPallet.RingStatus(total: 10, included: 10)
        recyclerLoader.revisions[key] = 1

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService(recyclerLoader: recyclerLoader)

        let result = try await service.previewStrategy(
            amount: planks(Decimal(25)),
            availableCoins: [],
            availableVouchers: [voucher],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        try await waitForPersistence(expectedSavedCoins: 3, expectedDeletedVouchers: 1) // $7 = $4 + $2 + $1

        #expect(mockVoucherService.deletedIdentifiers == [voucher.identifier])
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        // $32 - $25 = $7 change
        #expect(savedChangeValue == Decimal(7))
    }

    // MARK: - SplitCoin Strategy Tests

    @Test("Split strategy: overflow coin spent and change saved")
    func splitStrategyContextProcessing() async throws {
        // Given: $8 coin, need $5, should split into $5 recipient + $3 change
        let coin = makeCoin(exponent: 3, derivationIndex: 1) // $8

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService()

        // When
        let result = try await service.previewStrategy(
            amount: planks(Decimal(5)),
            availableCoins: [coin],
            availableVouchers: [],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        // Then
        try await waitForPersistence(expectedSpentCoins: 1, expectedSavedCoins: 2) // $3 = $2 + $1

        #expect(mockCoinService.markedSpentIds == [coin.identifier])
        let savedChangeValue = mockCoinService.savedCoins.reduce(Decimal(0)) {
            $0 + testContext.amount(forExponent: $1.exponent)
        }
        #expect(savedChangeValue == Decimal(3))
    }

    @Test("Split strategy with whole coins: all spent coins marked correctly")
    func splitWithWholeCoinsContextProcessing() async throws {
        // Given: $8 + $4 + $2 coins, need $11
        // Should use $8 + $4 whole ($12 total), split $4 for $3 + $1 change
        let coin1 = makeCoin(exponent: 3, derivationIndex: 1) // $8
        let coin2 = makeCoin(exponent: 2, derivationIndex: 2) // $4
        let coin3 = makeCoin(exponent: 1, derivationIndex: 3) // $2

        let context = TransferContext(coinService: mockCoinService, voucherService: mockVoucherService)

        let service = makeTransferSenderService()

        // When
        let result = try await service.previewStrategy(
            amount: planks(Decimal(11)),
            availableCoins: [coin1, coin2, coin3],
            availableVouchers: [],
            breakdownContext: testContext
        )
        _ = try await service.execute(
            result: result,
            currentDate: now,
            breakdownContext: testContext,
            context: context
        )

        // Then - coins used in split are marked spent
        try await waitForPersistence(expectedSpentCoins: 2, expectedSavedCoins: 1)

        #expect(Set(mockCoinService.markedSpentIds) == Set([coin1.identifier, coin2.identifier]))
        #expect(!mockCoinService.markedSpentIds.contains(coin3.identifier))
        #expect(mockVoucherService.deletedIdentifiers.isEmpty)
    }
}

extension TransferSenderServiceTests {
    // MARK: - Helpers

    private func waitForPersistence(
        expectedSpentCoins: Int = 0,
        expectedSavedCoins: Int = 0,
        expectedDeletedVouchers: Int = 0,
        timeout: TimeInterval = 2.0
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let actualSpent = mockCoinService.markedSpentIds.count
            let actualSaved = mockCoinService.savedCoins.count
            let actualDeleted = mockVoucherService.deletedIdentifiers.count

            if actualSpent >= expectedSpentCoins,
               actualSaved >= expectedSavedCoins,
               actualDeleted >= expectedDeletedVouchers {
                return
            }

            try await Task.sleep(for: .milliseconds(20)) // 20ms
        }
    }

    private func planks(_ decimal: Decimal) -> BigUInt {
        decimal.toSubstrateAmount(precision: testContext.precision)!
    }

    private func makeCoin(
        exponent: Int16,
        derivationIndex: UInt32 = 0,
        age: Int16 = 0,
        state: Coin.State = .available
    ) -> Coin {
        Coin(exponent: exponent, derivationIndex: derivationIndex, age: age, state: state)
    }

    private func makeVoucher(
        exponent: Int16,
        derivationIndex: UInt32,
        recyclerIndex: UInt32 = 0,
        readyAt: Date = Date.distantPast
    ) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: Date.distantPast,
            readyAt: readyAt,
            remoteState: .inRecycler(.init(index: recyclerIndex))
        )
    }

    private func makeTransferSenderService(
        coinAllocator: MockCoinAllocator = MockCoinAllocator(),
        coordinator: MockExtrinsicSubmissionCoordinator = MockExtrinsicSubmissionCoordinator(),
        originFactory: MockOriginFactory = MockOriginFactory(),
        recyclerLoader: MockRecyclerLoader = MockRecyclerLoader(),
        blockInfoProvider: MockBlockNumberProvider = MockBlockNumberProvider()
    ) -> TransferSenderService {
        let coinSelector = CoinSelector()
        let memoBuilder = MockMemoBuilder()
        let coinKeyFactory = MockCoinKeyFactory()
        let voucherKeyFactory = MockVoucherKeyFactory()

        let planFactory = TransferPlanFactory(
            coinAllocator: coinAllocator,
            voucherKeyFactory: voucherKeyFactory,
            coinKeyFactory: coinKeyFactory,
            coordinator: coordinator,
            originFactory: originFactory,
            recyclerLoader: recyclerLoader,
            walStore: MockTransferWALStore(),
            blockInfoProvider: blockInfoProvider,
            logger: nil
        )

        return TransferSenderService(
            coinSelector: coinSelector,
            planFactory: planFactory,
            memoBuilder: memoBuilder,
            recyclerLoader: recyclerLoader,
            logger: nil
        )
    }
}
