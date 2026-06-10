import Testing
import Foundation
import BigInt
import KeyDerivation
import Operation_iOS
import SubstrateSdk
import AsyncExtensions
import FoundationExt
@testable import Coinage

@Suite("CoinageService Tests", .disabled())
struct CoinageServiceTests {
    // MARK: - Test Helpers

    struct TimeoutError: Error {}

    private func waitForStreamCondition<T>(
        _ stream: AnyAsyncSequence<T>,
        timeout: TimeInterval = 2.0,
        condition: @escaping @Sendable (T) -> Bool
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await value in stream {
                    if condition(value) { return }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !Task.isCancelled {
                    throw TimeoutError()
                }
            }
            // Wait for whichever finishes first (either condition met, or timeout)
            try await group.next()
            group.cancelAll()
        }
    }

    private func makeBreakdownContext() -> DenominationBreakdownContext {
        DenominationBreakdownContext(
            unit: BigUInt(10).power(16),
            precision: 18,
            maxExponent: 7,
            minExponent: 0
        )
    }

    private func plank(from decimal: Decimal) -> BigUInt {
        decimal.toSubstrateAmount(precision: makeBreakdownContext().precision)!
    }

    private func makeCoin(derivationIndex: UInt32, exponent: Int16, state: Coin.State = .available) -> Coin {
        Coin(
            exponent: exponent,
            derivationIndex: derivationIndex,
            age: 0,
            state: state
        )
    }

    private func makeVoucher(
        derivationIndex: UInt32,
        exponent: Int16,
        state: Voucher.OnChainState = .unlocated,
        readyAt: Date = Date.distantPast
    ) -> Voucher {
        Voucher(
            exponent: exponent,
            derivationIndex: derivationIndex,
            allocatedAt: Date(),
            readyAt: readyAt,
            remoteState: state
        )
    }

    private func makeTransferExpectation(
        memo: TransferMemo = TransferMemo(entries: [], totalValue: BigUInt(0)),
        changeCoins: [Coin] = [],
        spentCoins: [Coin] = [],
        spentVouchers: [Voucher] = []
    ) -> MockTransferSenderService.TransferExpectation {
        MockTransferSenderService.TransferExpectation(
            memo: memo,
            changeCoins: changeCoins,
            spentCoins: spentCoins,
            spentVouchers: spentVouchers
        )
    }

    private func makeSUT(
        coinService: MockCoinService = MockCoinService(),
        voucherService: MockVoucherService = MockVoucherService(),
        transferService: MockTransferSenderService = MockTransferSenderService(),
        recipientService: MockTransferRecipientService = MockTransferRecipientService(),
        contextLoader: MockDenominationContextLoader = MockDenominationContextLoader(),
        recyclingService: MockRecyclingService = MockRecyclingService(),
        coinProvider: StreamableProvider<Coin> = makeStreamableProvider(models: []),
        voucherProvider: StreamableProvider<Voucher> = makeStreamableProvider(models: [])
    ) -> CoinageService {
        contextLoader.contextToReturn = makeBreakdownContext()
        return CoinageService(
            coinService: coinService,
            voucherService: voucherService,
            senderService: transferService,
            ongoingTransferService: recipientService,
            transferRecoveryService: MockTransferRecoveryService(),
            externalPaymentService: MockExternalPaymentService(),
            contextLoader: contextLoader,
            recyclingService: recyclingService,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            coinProvider: coinProvider,
            voucherProvider: voucherProvider,
            recoveryService: MockCoinageBackupRecoveryService()
        )
    }

    private static func makeStreamableProvider<T: Identifiable>(models: [T]) -> StreamableProvider<T> {
        let source = AnyStreamableSource(MockStreamableSource<T>())
        let repository = AnyDataProviderRepository(MockRepository(models: models))
        let observable = AnyDataProviderRepositoryObservable(MockObservable<T>(models: models))

        return StreamableProvider(
            source: source,
            repository: repository,
            observable: observable,
            operationManager: OperationManager(operationQueue: OperationQueue())
        )
    }

    private func makeAsset(precision: Int16 = 18) -> MockAsset {
        MockAsset(decimalPrecision: precision)
    }

    // MARK: - Setup Tests

    @Test("setup fetches context from loader")
    func setupFetchesContextFromLoader() async throws {
        // Given
        let mockLoader = MockDenominationContextLoader()
        mockLoader.contextToReturn = makeBreakdownContext()
        let sut = makeSUT(contextLoader: mockLoader)
        let asset = makeAsset()

        // When
        try await sut.setup(with: asset)

        // Then
        #expect(mockLoader.fetchCallCount == 1)
        #expect(mockLoader.receivedAsset?.decimalPrecision == asset.decimalPrecision)
    }

    @Test("setup calls recyclingService.scheduleRecycling()")
    func setupStartsRecyclingService() async throws {
        let mockRecyclingService = MockRecyclingService()
        let mockLoader = MockDenominationContextLoader()
        mockLoader.contextToReturn = makeBreakdownContext()

        let sut = CoinageService(
            coinService: MockCoinService(),
            voucherService: MockVoucherService(),
            senderService: MockTransferSenderService(),
            ongoingTransferService: MockTransferRecipientService(),
            transferRecoveryService: MockTransferRecoveryService(),
            externalPaymentService: MockExternalPaymentService(),
            contextLoader: mockLoader,
            recyclingService: mockRecyclingService,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            coinProvider: Self.makeStreamableProvider(models: [Coin]()),
            voucherProvider: Self.makeStreamableProvider(models: [Voucher]()),
            recoveryService: MockCoinageBackupRecoveryService()
        )

        try await sut.setup(with: makeAsset())

        let count = await mockRecyclingService.scheduleCallCount
        #expect(count == 1)
    }

    @Test("setup updates existing context with withChanging")
    func setupUpdatesExistingContext() async throws {
        // Given
        let mockLoader = MockDenominationContextLoader()
        mockLoader.contextToReturn = makeBreakdownContext()
        let sut = makeSUT(contextLoader: mockLoader)

        // First setup
        try await sut.setup(with: makeAsset(precision: 18))
        let fetchCountAfterFirst = mockLoader.fetchCallCount

        // When - second setup with different precision
        try await sut.setup(with: makeAsset(precision: 12))

        // Then - loader should not be called again (uses withChanging)
        #expect(mockLoader.fetchCallCount == fetchCountAfterFirst)
    }

    // MARK: - notConfigured Error Tests

    @Test("transfer throws notConfigured before setup")
    func transferThrowsNotConfiguredBeforeSetup() async throws {
        // Given
        let sut = makeSUT()

        // When / Then
        await #expect(throws: CoinageError.notConfigured) {
            try await sut.previewTransfer(for: plank(from: Decimal(string: "0.01")!))
        }
    }

    // MARK: - requireContext Waiter Tests

    @Test("coinageBalanceService waits for concurrent setup")
    func requireContextWaitsForConcurrentSetup() async throws {
        let mockLoader = MockDenominationContextLoader()
        mockLoader.contextToReturn = makeBreakdownContext()
        let sut = makeSUT(contextLoader: mockLoader)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { _ = try await sut.coinageBalanceService() }
            group.addTask { try await sut.setup(with: makeAsset()) }
            try await group.waitForAll()
        }
    }

    @Test("coinageBalanceService propagates setup failure to waiters")
    func requireContextPropagatesSetupFailure() async throws {
        struct LoaderError: Error, Equatable {}

        let mockLoader = MockDenominationContextLoader()
        mockLoader.shouldThrow = LoaderError()
        let sut = makeSUT(contextLoader: mockLoader)

        // Run setup (which will fail) concurrently with the caller
        let setupTask = Task { try? await sut.setup(with: makeAsset()) }

        await #expect(throws: LoaderError.self) {
            _ = try await sut.coinageBalanceService()
        }
        await setupTask.value
    }

    @Test("coinageBalanceService succeeds on retry after failed setup")
    func requireContextSucceedsOnRetry() async throws {
        struct LoaderError: Error {}

        let mockLoader = MockDenominationContextLoader()
        mockLoader.shouldThrow = LoaderError()
        let sut = makeSUT(contextLoader: mockLoader)
        let asset = makeAsset()

        // First setup fails
        try? await sut.setup(with: asset)

        // Fix loader for retry
        mockLoader.shouldThrow = nil
        mockLoader.contextToReturn = makeBreakdownContext()

        // Concurrent caller and retry both succeed
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { _ = try await sut.coinageBalanceService() }
            group.addTask { try await sut.setup(with: asset) }
            try await group.waitForAll()
        }
    }

    // MARK: - Transfer Tests

    @Test("transfer returns TransferMemo after successful execution")
    func transferReturnsTransferMemo() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        let coin = makeCoin(derivationIndex: 1, exponent: 3) // 0.08
        mockCoinService.coinsToReturn = [coin]
        mockVoucherService.vouchersToReturn = []

        let expectedMemo = TransferMemo(entries: [Data([0x01, 0x02])], totalValue: BigUInt(10).power(16))
        let expectation = makeTransferExpectation(
            memo: expectedMemo,
            changeCoins: [],
            spentCoins: [coin],
            spentVouchers: []
        )
        await mockTransferService.setExpectation(expectation)

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [coin])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When
        let preview = try await sut.previewTransfer(for: plank(from: Decimal(string: "0.01")!))
        let memo = try await sut.executeTransfer(result: preview.selectionResult)

        // Then
        #expect(memo == expectedMemo)
        let receivedAmount = await mockTransferService.receivedAmount
        #expect(receivedAmount == plank(from: Decimal(string: "0.01")!))
    }

    // MARK: - Persistence Tests

    @Test("persists change coins after transfer")
    func persistsChangeCoins() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        let inputCoin = makeCoin(derivationIndex: 1, exponent: 3) // 0.08
        let changeCoin = makeCoin(derivationIndex: 2, exponent: 2) // 0.04 change
        mockCoinService.coinsToReturn = [inputCoin]
        mockVoucherService.vouchersToReturn = []

        let expectation = makeTransferExpectation(
            changeCoins: [changeCoin],
            spentCoins: [inputCoin]
        )
        await mockTransferService.setExpectation(expectation)

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [inputCoin])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When
        let preview = try await sut.previewTransfer(for: plank(from: Decimal(string: "0.04")!))
        _ = try await sut.executeTransfer(result: preview.selectionResult)

        // Then
        #expect(mockCoinService.savedCoins == [changeCoin])
    }

    @Test("marks spent coins after transfer")
    func marksSpentCoins() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        let spentCoin1 = makeCoin(derivationIndex: 1, exponent: 0)
        let spentCoin2 = makeCoin(derivationIndex: 2, exponent: 1)
        mockCoinService.coinsToReturn = [spentCoin1, spentCoin2]
        mockVoucherService.vouchersToReturn = []

        let expectation = makeTransferExpectation(
            spentCoins: [spentCoin1, spentCoin2]
        )
        await mockTransferService.setExpectation(expectation)

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [spentCoin1, spentCoin2])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When
        let preview = try await sut.previewTransfer(for: plank(from: Decimal(string: "0.03")!))
        _ = try await sut.executeTransfer(result: preview.selectionResult)

        // Then
        #expect(Set(mockCoinService.markedSpentIds) == Set(["1", "2"]))
    }

    @Test("deletes spent vouchers after transfer")
    func deletesSpentVouchers() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        let coin = makeCoin(derivationIndex: 1, exponent: 3) // 0.08
        let spentVoucher = makeVoucher(
            derivationIndex: 10,
            exponent: 2,
            readyAt: Date.distantPast
        )
        mockCoinService.coinsToReturn = [coin]
        mockVoucherService.vouchersToReturn = [spentVoucher]

        let expectation = makeTransferExpectation(
            spentCoins: [],
            spentVouchers: [spentVoucher]
        )
        await mockTransferService.setExpectation(expectation)

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [coin]),
            voucherProvider: Self.makeStreamableProvider(models: [spentVoucher])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When
        let preview = try await sut.previewTransfer(for: plank(from: Decimal(string: "0.04")!))
        _ = try await sut.executeTransfer(result: preview.selectionResult)

        // Then
        #expect(mockVoucherService.deletedIdentifiers == ["10"])
    }

    // MARK: - Error Handling Tests

    @Test("transfer fails with insufficientBalance when amount exceeds spendable")
    func transferFailsWithInsufficientBalance() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        // Only 0.01 spendable
        let coin = makeCoin(derivationIndex: 1, exponent: 0)
        mockCoinService.coinsToReturn = [coin]
        mockVoucherService.vouchersToReturn = []

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [coin])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When / Then
        await #expect(throws: CoinageError.self) {
            try await sut.previewTransfer(for: plank(from: Decimal(string: "0.05")!)) // Request more than available
        }
    }

    // MARK: - Persistence Order Tests

    @Test("persistence order is save -> markSpent -> delete")
    func persistenceOrderIsCorrect() async throws {
        // Given
        let mockCoinService = MockCoinService()
        let mockVoucherService = MockVoucherService()
        let mockTransferService = MockTransferSenderService()

        let callOrderTracker = CallOrderTracker()
        mockCoinService.callOrderTracker = callOrderTracker
        mockVoucherService.callOrderTracker = callOrderTracker

        let inputCoin = makeCoin(derivationIndex: 1, exponent: 3) // 0.08
        let changeCoin = makeCoin(derivationIndex: 2, exponent: 2)
        let spentVoucher = makeVoucher(derivationIndex: 10, exponent: 0, readyAt: Date.distantPast)
        mockCoinService.coinsToReturn = [inputCoin]
        mockVoucherService.vouchersToReturn = [spentVoucher]

        let expectation = makeTransferExpectation(
            changeCoins: [changeCoin],
            spentCoins: [inputCoin],
            spentVouchers: [spentVoucher]
        )
        await mockTransferService.setExpectation(expectation)

        let sut = makeSUT(
            coinService: mockCoinService,
            voucherService: mockVoucherService,
            transferService: mockTransferService,
            coinProvider: Self.makeStreamableProvider(models: [inputCoin]),
            voucherProvider: Self.makeStreamableProvider(models: [spentVoucher])
        )
        try await sut.setup(with: makeAsset())

        // Wait for the mocked provider streams to process and populate the spendable balance
        let balanceService = try await sut.coinageBalanceService()
        try await waitForStreamCondition(balanceService.spendableBalanceStream) { $0.fullPrivacy.balanceInDecimal() > 0
        }

        // When
        let preview = try await sut.previewTransfer(for: plank(from: Decimal(string: "0.04")!))
        _ = try await sut.executeTransfer(result: preview.selectionResult)

        // Then - verify order: save (1) -> markSpent (2) -> delete (3)
        #expect(mockCoinService.saveCallOrder == 1)
        #expect(mockCoinService.markSpentCallOrder == 2)
        #expect(mockVoucherService.deleteCallOrder == 3)
    }
}

// MARK: - Test Doubles

private extension CoinageServiceTests {
    /// Mock asset that provides decimalPrecision for context creation.
    struct MockAsset: AssetProtocol {
        var symbol: String = "HOLLAR"

        let assetId: AssetId = 0
        let isUtility: Bool = true
        let decimalPrecision: Int16
    }

    // MARK: - StreamableProvider Mocks

    final class MockStreamableSource<T: Identifiable>: StreamableSourceProtocol, @unchecked Sendable {
        typealias Model = T
        func fetchHistory(runningIn queue: DispatchQueue?, commitNotificationBlock: ((Result<Int, Error>?) -> Void)?) {
            if let queue {
                queue.async { commitNotificationBlock?(.success(0)) }
            } else {
                commitNotificationBlock?(.success(0))
            }
        }

        func refresh(runningIn queue: DispatchQueue?, commitNotificationBlock: ((Result<Int, Error>?) -> Void)?) {
            if let queue {
                queue.async { commitNotificationBlock?(.success(0)) }
            } else {
                commitNotificationBlock?(.success(0))
            }
        }
    }

    final class ResultOperation<T>: BaseOperation<T>, @unchecked Sendable {
        let value: T
        init(value: T) {
            self.value = value
            super.init()
        }

        override func main() {
            result = .success(value)
        }
    }

    final class MockRepository<T: Identifiable>: DataProviderRepositoryProtocol, @unchecked Sendable {
        typealias Model = T
        let models: [T]

        init(models: [T]) {
            self.models = models
        }

        func fetchOperation(
            by modelIdClosure: @escaping () throws -> String,
            options _: RepositoryFetchOptions
        ) -> BaseOperation<T?> {
            ResultOperation(value: (try? modelIdClosure()).flatMap { id in
                models.first { $0.identifier == id }
            })
        }

        func fetchAllOperation(with _: RepositoryFetchOptions) -> BaseOperation<[T]> {
            ResultOperation(value: models)
        }

        func fetchOperation(by _: RepositorySliceRequest, options _: RepositoryFetchOptions) -> BaseOperation<[T]> {
            ResultOperation(value: models)
        }

        func saveOperation(_: @escaping () throws -> [T], _: @escaping () throws -> [String]) -> BaseOperation<Void> {
            ResultOperation(value: ())
        }

        func replaceOperation(_: @escaping () throws -> [T]) -> BaseOperation<Void> {
            ResultOperation(value: ())
        }

        func fetchCountOperation() -> BaseOperation<Int> {
            ResultOperation(value: models.count)
        }

        func deleteAllOperation() -> BaseOperation<Void> {
            ResultOperation(value: ())
        }
    }

    final class MockObservable<T: Identifiable>: DataProviderRepositoryObservable, @unchecked Sendable {
        typealias Model = T
        let models: [T]

        init(models: [T]) {
            self.models = models
        }

        func start(completionBlock: @escaping (Error?) -> Void) { completionBlock(nil) }
        func stop(completionBlock: @escaping (Error?) -> Void) { completionBlock(nil) }
        func addObserver(
            _: AnyObject,
            deliverOn queue: DispatchQueue,
            executing updateBlock: @escaping ([DataProviderChange<T>]) -> Void
        ) {
            let changes = models.map { DataProviderChange.insert(newItem: $0) }
            queue.async {
                updateBlock(changes)
            }
        }

        func removeObserver(_: AnyObject) {}
    }

    /// Tracks call order for verifying persistence sequence
    final class CallOrderTracker: @unchecked Sendable {
        var currentOrder: Int = 0

        func nextOrder() -> Int {
            currentOrder += 1
            return currentOrder
        }
    }

    final class MockDenominationContextLoader: DenominationContextLoaderProtocol, @unchecked Sendable {
        var contextToReturn: DenominationBreakdownContext?
        var shouldThrow: Error?
        var receivedAsset: (any AssetProtocol)?
        var fetchCallCount = 0

        func fetchContext(for asset: AssetProtocol) async throws -> DenominationBreakdownContext {
            fetchCallCount += 1
            receivedAsset = asset
            if let error = shouldThrow {
                throw error
            }
            guard let context = contextToReturn else {
                fatalError("MockDenominationContextLoader: contextToReturn not set")
            }
            return context
        }
    }

    final class MockCoinService: CoinServiceProtocol, @unchecked Sendable {
        func markRecycling(coinIds: [String]) async throws {
            if let error = shouldThrow {
                throw error
            }
            markedRecyclingIds = coinIds
            markRecyclingCallOrder = callOrderTracker?.nextOrder()
        }

        func markAvailable(coinIds: [String]) async throws {
            if let error = shouldThrow {
                throw error
            }
            markedAvailableIds = coinIds
            markAvailableCallOrder = callOrderTracker?.nextOrder()
        }

        var coinsToReturn: [Coin] = []
        var savedCoins: [Coin] = []
        var markedSpentIds: [String] = []
        var markedAvailableIds: [String] = []
        var markedRecyclingIds: [String] = []
        var shouldThrow: Error?

        var saveCallOrder: Int?
        var markSpentCallOrder: Int?
        var markRecyclingCallOrder: Int?
        var markAvailableCallOrder: Int?
        var callOrderTracker: CallOrderTracker?

        func fetchAllCoins() async throws -> [Coin] {
            if let error = shouldThrow {
                throw error
            }
            return coinsToReturn
        }

        func save(coins: [Coin]) async throws {
            if let error = shouldThrow {
                throw error
            }
            savedCoins = coins
            saveCallOrder = callOrderTracker?.nextOrder()
        }

        func markSpent(coinIds: [String]) async throws {
            if let error = shouldThrow {
                throw error
            }
            markedSpentIds = coinIds
            markSpentCallOrder = callOrderTracker?.nextOrder()
        }

        func markPendingTransfer(coinIds _: [String]) async throws {}
    }

    final class MockVoucherService: VoucherServiceProtocol, @unchecked Sendable {
        var vouchersToReturn: [Voucher] = []
        var deletedIdentifiers: [String] = []
        var shouldThrow: Error?

        var deleteCallOrder: Int?
        var callOrderTracker: CallOrderTracker?

        var loadCallWallets: [any WalletManaging] = []

        func load(
            amount _: BigUInt,
            externalAssetHolder: any WalletManaging,
            breakdownContext _: DenominationBreakdownContext
        ) async throws {
            loadCallWallets.append(externalAssetHolder)
            if let error = shouldThrow {
                throw error
            }
        }

        func fetchAll() async throws -> [Voucher] {
            if let error = shouldThrow {
                throw error
            }
            return vouchersToReturn
        }

        func fetchAvailableInRecycler() async throws -> [Voucher] {
            try await fetchAll().filter(\.remoteState.isInRecycler)
        }

        func save(vouchers _: [Voucher]) async throws {}

        func markAvailable(identifiers _: [String]) async throws {}

        func markPendingTransfer(identifiers _: [String]) async throws {}

        func markPendingOnboarding(identifiers _: [String]) async throws {}

        func delete(identifiers: [String]) async throws {
            if let error = shouldThrow {
                throw error
            }
            deletedIdentifiers = identifiers
            deleteCallOrder = callOrderTracker?.nextOrder()
        }
    }

    final actor MockTransferRecipientService: OngoingTransferServicing {
        nonisolated(unsafe) var receivedMemo: TransferMemo?
        nonisolated(unsafe) var receivedMessageId: String?
        nonisolated(unsafe) var shouldThrow: Error?

        func claim(memo: Coinage.TransferMemo, messageId: String) async throws {
            receivedMemo = memo
            receivedMessageId = messageId
            if let error = shouldThrow {
                throw error
            }
        }

        func awaitSendOnChain(memo _: TransferMemo, blockTimeout _: UInt32) async throws {
            if let error = shouldThrow {
                throw error
            }
        }

        func awaitClaimOnChain(memo _: TransferMemo, blockTimeout _: UInt32) async throws {
            if let error = shouldThrow {
                throw error
            }
        }

        func transferCoinsFromSecretKeys(
            secretKeys _: [Data],
            transferCoins _: Bool,
            context _: DenominationBreakdownContext
        ) async throws -> BigUInt {
            if let error = shouldThrow {
                throw error
            }
            return 0
        }
    }

    final class MockCoinageBackupRecoveryService: CoinageBackupRecoveryServicing {
        func recoverCoins() async throws -> Coinage.ScanResult<Coinage.Coin> {
            ScanResult(items: [], horizon: 0)
        }

        func recoverVouchers() async throws -> Coinage.ScanResult<Coinage.Voucher> {
            ScanResult(items: [], horizon: 0)
        }

        func extendScanCoins(from _: Int) async throws -> Coinage.ScanResult<Coinage.Coin> {
            ScanResult(items: [], horizon: 0)
        }

        func extendScanVouchers(from _: Int) async throws -> Coinage.ScanResult<Coinage.Voucher> {
            ScanResult(items: [], horizon: 0)
        }
    }

    final actor MockTransferRecoveryService: TransferRecoveryServicing {
        func recover() async {}
    }

    final class MockExternalPaymentService: ExternalPaymentServicing {
        func previewPayment(
            for _: Balance,
            context _: DenominationBreakdownContext
        ) async throws -> ExternalPaymentPreview {
            .notEnoughBalance
        }

        func initiatePayment(
            origin _: String,
            amountInPlanks _: Balance,
            destination _: AccountId
        ) async throws -> String {
            UUID().uuidString
        }

        func subscribePaymentStatus(
            paymentId _: String
        ) throws -> AnyAsyncSequence<ExternalPaymentStatus> {
            AsyncStream<ExternalPaymentStatus> { $0.finish() }
                .eraseToAnyAsyncSequence()
        }

        func setup(with _: DenominationBreakdownContext) {}
        func throttle() {}
    }

    final actor MockRecyclingService: CoinageRecyclingServicing {
        var scheduleCallCount = 0

        func scheduleRecycling() async {
            scheduleCallCount += 1
        }

        func recycleCoins(_: [Coin]) async throws {}
    }

    final actor MockTransferSenderService: TransferSenderServicing {
        struct TransferExpectation {
            let memo: TransferMemo
            let changeCoins: [Coin]
            let spentCoins: [Coin]
            let spentVouchers: [Voucher]
        }

        nonisolated(unsafe) var expectationToReturn: TransferExpectation?
        nonisolated(unsafe) var shouldThrow: Error?
        nonisolated(unsafe) var receivedAmount: BigUInt?
        nonisolated(unsafe) var receivedCoins: [Coin]?
        nonisolated(unsafe) var receivedVouchers: [Voucher]?
        nonisolated(unsafe) var receivedBreakdownContext: DenominationBreakdownContext?
        nonisolated(unsafe) var receivedResult: CoinSelectionResult?

        func setExpectation(_ expectation: TransferExpectation) {
            expectationToReturn = expectation
        }

        func previewStrategy(
            amount: BigUInt,
            availableCoins: [Coin],
            availableVouchers: [Voucher],
            breakdownContext: DenominationBreakdownContext
        ) async throws -> CoinSelectionResult {
            receivedAmount = amount
            receivedCoins = availableCoins
            receivedVouchers = availableVouchers
            receivedBreakdownContext = breakdownContext

            if let error = shouldThrow {
                throw error
            }

            guard let expectation = expectationToReturn else {
                fatalError("MockTransferSenderService: expectationToReturn not set")
            }

            let result: CoinSelectionResult = .exactMatch(coins: expectation.spentCoins)

            receivedResult = result
            return result
        }

        func execute(
            result _: CoinSelectionResult,
            currentDate _: Date,
            breakdownContext _: DenominationBreakdownContext,
            context: TransferContext
        ) async throws -> TransferMemo {
            if let error = shouldThrow {
                throw error
            }

            guard let expectation = expectationToReturn else {
                fatalError("MockTransferSenderService: expectationToReturn not set")
            }

            // Simulate what a real strategy would do - persist state via context
            try await context.process(
                spentCoins: expectation.spentCoins,
                spentVouchers: expectation.spentVouchers,
                change: expectation.changeCoins
            )

            return expectation.memo
        }
    }

    final class MockWallet: WalletManaging {
        func fetchAccount(for _: ChainProtocol) throws -> AccountProtocol {
            fatalError("MockWallet.fetchAccount not implemented")
        }

        func hasAccount(in _: ChainProtocol) -> Bool { false }

        func getRawPublicKey() throws -> Data { Data(repeating: 0x00, count: 32) }

        func fetchRawSecretKey() throws -> Data {
            Data(repeating: 0x00, count: 64)
        }

        func fetchSignerSecret(for _: SignerProviding) throws -> Data {
            Data(repeating: 0x00, count: 32)
        }

        func getMultiSigner() throws -> MultiSigner { .sr25519(Data(repeating: 0x00, count: 32)) }

        func sign(data _: Data) throws -> MultiSignature {
            .sr25519(data: Data(repeating: 0x00, count: 64))
        }
    }
}
