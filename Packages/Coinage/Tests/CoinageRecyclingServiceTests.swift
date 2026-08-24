import Testing
import Foundation
import Operation_iOS
import ExtrinsicService
import KeyDerivation
import BandersnatchApi
import SubstrateSdk
import SDKLogger
@testable import Coinage

@Suite("CoinageRecyclingService Tests")
struct CoinageRecyclingServiceTests {
    // MARK: - Eligibility

    @Test("Only available coins at or above the recycle age are recycled")
    func recyclesOnlyEligibleCoins() async throws {
        let sut = makeSUT(coins: [
            makeCoin(index: 1, age: 13),
            makeCoin(index: 2, age: 14),
            makeCoin(index: 3, age: 16)
        ])

        await sut.service.recycleOldCoins()

        #expect(Set(sut.coinService.ids(for: "recycling")) == ["2", "3"])
        #expect(Set(sut.coinService.ids(for: "spent")) == ["2", "3"])
    }

    @Test("Coins with unknown age or a non-available state are skipped")
    func skipsNonAvailableAndUnknownAge() async throws {
        let sut = makeSUT(coins: [
            makeCoin(index: 1, age: 16),
            makeCoin(index: 2, age: 16, state: .spent),
            makeCoin(index: 3, age: 16, state: .recycling),
            makeCoin(index: 4, age: nil)
        ])

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["1"])
    }

    @Test("Eligible coins are processed oldest first")
    func processesOldestFirst() async throws {
        let sut = makeSUT(coins: [
            makeCoin(index: 1, age: 14),
            makeCoin(index: 2, age: 16),
            makeCoin(index: 3, age: 15)
        ])

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["2", "3", "1"])
    }

    // MARK: - Per-coin outcomes

    @Test("Success locks then spends the coin, persists the voucher available, and registers")
    func successRecyclesCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)])

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.events.map(\.action) == ["recycling", "spent"])
        #expect(sut.coinService.ids(for: "available").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.count == 1)
        #expect(sut.voucherRepo.savedVouchers.first?.localState == .available)
        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
        #expect(entries.first?.inputs == [.coin(.own(7))])
        #expect(entries.first?.outputs.count == 1)
    }

    @Test("On-chain failure spends the coin, drops the voucher, and registers")
    func chainFailureDestroysCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], submissionOutcome: .chainFailure)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "spent") == ["7"])
        #expect(sut.coinService.ids(for: "available").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.isEmpty)
        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
    }

    @Test("A pre-submission error reverts the coin and registers no entry")
    func preSubmissionErrorRevertsCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], allocatorError: StubError.boom)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["7"])
        #expect(sut.coinService.ids(for: "available") == ["7"])
        #expect(sut.coinService.ids(for: "spent").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.isEmpty)
        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.isEmpty)
    }

    @Test("A thrown submission leaves the entry and the coin in .recycling for recovery")
    func thrownSubmissionLeavesWALForRecovery() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], submissionOutcome: .thrown)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["7"])
        #expect(sut.coinService.ids(for: "spent").isEmpty)
        #expect(sut.coinService.ids(for: "available").isEmpty)

        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
        #expect(entries.first?.status == .pending)
        #expect(entries.first?.inputs == [.coin(.own(7))])
        #expect(entries.first?.outputs.count == 1)
        #expect(sut.voucherRepo.savedVouchers.first?.localState == .pendingOnboarding)
    }

    @Test("recycleCoins rethrows on a pre-submission failure")
    func recycleCoinsRethrows() async throws {
        let sut = makeSUT(allocatorError: StubError.boom)

        await #expect(throws: StubError.self) {
            try await sut.service.recycleCoins([makeCoin(index: 7, age: 14)])
        }
    }

    // MARK: - Scheduling

    @Test("scheduleRecycling arms the background task and recycles")
    func scheduleRecyclingArmsAndRecycles() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 1, age: 14)], backgroundRecyclingInterval: 3_600)

        await sut.service.scheduleRecycling()

        #expect(sut.coinService.ids(for: "recycling") == ["1"])
        #expect(await sut.scheduler.scheduleCount == 1)
        #expect(await sut.scheduler.lastEarliestBegin == 3_600)
    }

    @Test("Foreground recycling recycles without arming a background task")
    func foregroundRecyclingRuns() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 1, age: 14)])

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["1"])
        #expect(await sut.scheduler.scheduleCount == 0)
    }
}

// MARK: - SUT

private extension CoinageRecyclingServiceTests {
    struct SUT {
        let service: CoinageRecyclingService
        let coinService: RecyclingMockCoinService
        let scheduler: RecordingScheduler
        let voucherRepo: RecordingVoucherRepository
        let durabilityService: MockDurabilityService
    }

    func makeSUT(
        coins: [Coin] = [],
        submissionOutcome: MockDurabilityService.SubmissionOutcome = .success,
        allocatorError: Error? = nil,
        backgroundRecyclingInterval: TimeInterval = 3_600,
        recycleAtAge: Int16 = 14
    ) -> SUT {
        let coinService = RecyclingMockCoinService(coins: coins)
        let scheduler = RecordingScheduler()
        let voucherRepo = RecordingVoucherRepository()
        let durabilityService = MockDurabilityService(submissionOutcome: submissionOutcome)

        let service = CoinageRecyclingService(
            schedulerFactory: RecordingSchedulerFactory(scheduler: scheduler),
            coinService: coinService,
            voucherAllocator: StubVoucherAllocator(error: allocatorError),
            voucherRepository: AnyDataProviderRepository(voucherRepo),
            coinKeypairFactory: StubCoinKeyFactory(),
            voucherKeypairFactory: StubVoucherKeyFactory(),
            durability: durabilityService,
            originFactory: StubOriginFactory(),
            logger: StubLogger(),
            backgroundRecyclingInterval: backgroundRecyclingInterval,
            recycleAtAge: recycleAtAge
        )

        return SUT(
            service: service,
            coinService: coinService,
            scheduler: scheduler,
            voucherRepo: voucherRepo,
            durabilityService: durabilityService
        )
    }

    func makeCoin(index: UInt32, age: Int16?, state: Coin.State = .available) -> Coin {
        Coin(exponent: 3, derivationIndex: index, age: age, state: state)
    }
}

// MARK: - Mocks

private final class RecyclingMockCoinService: CoinServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let coins: [Coin]
    private var _events: [(action: String, ids: [String])] = []

    init(coins: [Coin]) {
        self.coins = coins
    }

    var events: [(action: String, ids: [String])] { lock.withLock { _events } }

    func ids(for action: String) -> [String] {
        lock.withLock { _events.filter { $0.action == action }.flatMap(\.ids) }
    }

    func fetchAllCoins() async throws -> [Coin] {
        coins
    }

    func save(coins _: [Coin]) async throws {}
    func markSpent(coinIds: [String]) async throws { record("spent", coinIds) }
    func markRecycling(coinIds: [String]) async throws { record("recycling", coinIds) }
    func markAvailable(coinIds: [String]) async throws { record("available", coinIds) }
    func markPendingTransfer(coinIds _: [String]) async throws {}
    func markPendingMint(coinIds: [String]) async throws { record("pendingMint", coinIds) }
    func markHandedOff(coinIds: [String]) async throws { record("handedOff", coinIds) }

    private func record(_ action: String, _ ids: [String]) {
        lock.withLock { _events.append((action, ids)) }
    }
}

private final class RecordingVoucherRepository: DataProviderRepositoryProtocol, @unchecked Sendable {
    typealias Model = Voucher

    private let lock = NSLock()
    private var _saved: [String: Voucher] = [:]

    var savedVouchers: [Voucher] { lock.withLock { Array(_saved.values) } }

    func saveOperation(
        _ updating: @escaping () throws -> [Voucher],
        _ deleting: @escaping () throws -> [String]
    ) -> BaseOperation<Void> {
        ClosureOperation { [self] in
            let vouchers = try updating()
            let deleted = try deleting()
            lock.withLock {
                for voucher in vouchers {
                    _saved[voucher.identifier] = voucher
                }
                for id in deleted {
                    _saved[id] = nil
                }
            }
        }
    }

    func fetchOperation(
        by _: @escaping () throws -> String,
        options _: RepositoryFetchOptions
    ) -> BaseOperation<Voucher?> {
        ClosureOperation<Voucher?> { nil }
    }

    func fetchAllOperation(with _: RepositoryFetchOptions) -> BaseOperation<[Voucher]> {
        ClosureOperation<[Voucher]> { [self] in lock.withLock { Array(_saved.values) } }
    }

    func fetchOperation(by _: RepositorySliceRequest, options _: RepositoryFetchOptions) -> BaseOperation<[Voucher]> {
        ClosureOperation<[Voucher]> { [] }
    }

    func replaceOperation(_: @escaping () throws -> [Voucher]) -> BaseOperation<Void> {
        ClosureOperation<Void> {}
    }

    func fetchCountOperation() -> BaseOperation<Int> {
        ClosureOperation<Int> { 0 }
    }

    func deleteAllOperation() -> BaseOperation<Void> {
        ClosureOperation<Void> {}
    }
}

private actor RecordingSchedulerFactory: CoinRecycleSchedulerMaking {
    private let scheduler: RecordingScheduler

    init(scheduler: RecordingScheduler) {
        self.scheduler = scheduler
    }

    func makeScheduler() -> CoinRecycleTaskScheduling {
        scheduler
    }
}

private final class RecordingScheduler: CoinRecycleTaskScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _scheduleCount = 0
    private var _lastEarliestBegin: TimeInterval?

    var scheduleCount: Int { lock.withLock { _scheduleCount } }
    var lastEarliestBegin: TimeInterval? { lock.withLock { _lastEarliestBegin } }

    func schedule(earliestBegin: TimeInterval) {
        lock.withLock {
            _scheduleCount += 1
            _lastEarliestBegin = earliestBegin
        }
    }

    func cancel() {}
}

private actor StubVoucherAllocator: VoucherAllocating {
    private var nextIndex: UInt32 = 500
    private let error: Error?

    init(error: Error?) {
        self.error = error
    }

    func allocate(exponent: Int16) async throws -> Voucher {
        if let error { throw error }
        let index = nextIndex
        nextIndex += 1
        return Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: Date(),
            readyAt: Date.distantPast,
            remoteState: .unlocated
        )
    }
}

private final class StubCoinKeyFactory: CoinKeyDeriving {
    typealias Model = Coin

    func derivePublicKey(for _: Coin) throws -> Data { Data(repeating: 0, count: 32) }
    func derivePrivateKey(for _: Coin) throws -> Data { Data(repeating: 0, count: 64) }
}

private final class StubVoucherKeyFactory: VoucherKeyDeriving {
    typealias Model = Voucher

    func derivePublicKey(for _: Voucher) throws -> Data { Data(repeating: 0, count: 32) }
    func derivePrivateKey(for _: Voucher) throws -> Data { Data(repeating: 0, count: 64) }

    func createKeyManager(for _: Voucher) throws -> any BandersnatchKeyManaging {
        StubBandersnatchKeyManager()
    }
}

private final class StubBandersnatchKeyManager: BandersnatchKeyManaging {
    func getRawPublicKey() throws -> Data { Data(repeating: 0, count: 32) }
    func sign(_: Data) throws -> Data { Data(repeating: 0, count: 32) }

    func createProof(
        _: Data,
        members _: [BandersnatchPubKey],
        context _: Data,
        domainSize _: BandersnatchApi.RingDomainSize
    ) throws -> Data {
        Data(repeating: 0, count: 64)
    }

    func deriveAlias(for _: Data) throws -> Data { Data(repeating: 0, count: 32) }
}

private final class StubOriginFactory: OriginCreating {
    func createAsCoinOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
        StubExtrinsicOrigin()
    }

    func createInfallibleUnpaidSignedOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
        StubExtrinsicOrigin()
    }

    func createAsUnloadTokenOrigins(
        voucherGroups: [[Voucher]],
        currentDate _: Date,
        blockHash _: BlockHashData?
    ) async throws -> [ExtrinsicOriginDefining] {
        voucherGroups.map { _ in StubExtrinsicOrigin() }
    }
}

private final class StubExtrinsicOrigin: ExtrinsicOriginDefining {
    func createOriginResolutionWrapper(
        for dependency: @escaping () throws -> ExtrinsicOriginDefinitionDependency,
        extrinsicVersion _: Extrinsic.Version,
        purpose _: ExtrinsicOriginPurpose
    ) -> CompoundOperationWrapper<ExtrinsicOriginDefinitionResponse> {
        let operation = ClosureOperation<ExtrinsicOriginDefinitionResponse> {
            let dep = try dependency()
            return ExtrinsicOriginDefinitionResponse(
                builders: dep.builders,
                senderResolution: dep.senderResolution,
                feePayment: dep.feePayment
            )
        }
        return CompoundOperationWrapper(targetOperation: operation)
    }
}

private final class StubLogger: SDKLoggerProtocol {
    func verbose(message _: String, file _: String, function _: String, line _: Int) {}
    func debug(message _: String, file _: String, function _: String, line _: Int) {}
    func info(message _: String, file _: String, function _: String, line _: Int) {}
    func warning(message _: String, file _: String, function _: String, line _: Int) {}
    func error(message _: String, file _: String, function _: String, line _: Int) {}
}
