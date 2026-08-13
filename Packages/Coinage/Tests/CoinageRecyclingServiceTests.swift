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

    @Test("Success locks then spends the coin, persists the voucher available, and clears the WAL")
    func successRecyclesCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)])

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.events.map(\.action) == ["recycling", "spent"])
        #expect(sut.coinService.ids(for: "available").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.count == 1)
        #expect(sut.voucherRepo.savedVouchers.first?.localState == .available)
        #expect(sut.coordinator.submittedWALIds.count == 1)
        #expect(await sut.walStore.entries.isEmpty)
    }

    @Test("On-chain failure spends the coin, drops the voucher, and clears the WAL")
    func chainFailureDestroysCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], submissionOutcome: .chainFailure)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "spent") == ["7"])
        #expect(sut.coinService.ids(for: "available").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.isEmpty)
        #expect(await sut.walStore.entries.isEmpty)
    }

    @Test("A pre-submission error reverts the coin and writes no WAL")
    func preSubmissionErrorRevertsCoin() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], allocatorError: StubError.boom)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["7"])
        #expect(sut.coinService.ids(for: "available") == ["7"])
        #expect(sut.coinService.ids(for: "spent").isEmpty)
        #expect(sut.voucherRepo.savedVouchers.isEmpty)
        #expect(await sut.walStore.entries.isEmpty)
    }

    @Test("A thrown submission leaves the WAL entry and the coin in .recycling for recovery")
    func thrownSubmissionLeavesWALForRecovery() async throws {
        let sut = makeSUT(coins: [makeCoin(index: 7, age: 14)], submissionOutcome: .thrown)

        await sut.service.recycleOldCoins()

        #expect(sut.coinService.ids(for: "recycling") == ["7"])
        #expect(sut.coinService.ids(for: "spent").isEmpty)
        #expect(sut.coinService.ids(for: "available").isEmpty)

        let entries = await sut.walStore.entries
        #expect(entries.count == 1)
        #expect(entries.first?.operationType == .recycleIntoVoucher)
        #expect(entries.first?.inputCoinIds == ["7"])
        #expect(entries.first?.expectedVoucherIndices.count == 1)
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
        let coordinator: StubSubmissionCoordinator
        let walStore: MockTransferWALStore
    }

    func makeSUT(
        coins: [Coin] = [],
        submissionOutcome: StubSubmissionCoordinator.Outcome = .success,
        allocatorError: Error? = nil,
        backgroundRecyclingInterval: TimeInterval = 3_600,
        recycleAtAge: Int16 = 14
    ) -> SUT {
        let coinService = RecyclingMockCoinService(coins: coins)
        let scheduler = RecordingScheduler()
        let voucherRepo = RecordingVoucherRepository()
        let coordinator = StubSubmissionCoordinator(outcome: submissionOutcome)
        let walStore = MockTransferWALStore()

        let service = CoinageRecyclingService(
            schedulerFactory: RecordingSchedulerFactory(scheduler: scheduler),
            coinService: coinService,
            voucherAllocator: StubVoucherAllocator(error: allocatorError),
            voucherRepository: AnyDataProviderRepository(voucherRepo),
            coinKeypairFactory: StubCoinKeyFactory(),
            voucherKeypairFactory: StubVoucherKeyFactory(),
            coordinator: coordinator,
            walStore: walStore,
            originFactory: StubOriginFactory(),
            logger: StubLogger(),
            backgroundRecyclingInterval: backgroundRecyclingInterval,
            mortality: 300,
            recycleAtAge: recycleAtAge
        )

        return SUT(
            service: service,
            coinService: coinService,
            scheduler: scheduler,
            voucherRepo: voucherRepo,
            coordinator: coordinator,
            walStore: walStore
        )
    }

    func makeCoin(index: UInt32, age: Int16?, state: Coin.State = .available) -> Coin {
        Coin(exponent: 3, derivationIndex: index, age: age, state: state)
    }
}

// MARK: - Mocks

enum StubError: Error {
    case boom
    case unexpected
}

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

private final class StubSubmissionCoordinator: ExtrinsicSubmissionCoordinating, @unchecked Sendable {
    enum Outcome {
        case success
        case chainFailure
        case thrown
    }

    private let lock = NSLock()
    private let outcome: Outcome
    private var _submittedWALIds: [UUID] = []

    var submittedWALIds: [UUID] { lock.withLock { _submittedWALIds } }

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func submit(
        walEntryId: UUID,
        builder _: @escaping ExtrinsicBuilderClosure,
        origin _: any ExtrinsicOriginDefining
    ) async throws -> ExtrinsicMonitorSubmission {
        lock.withLock { _submittedWALIds.append(walEntryId) }
        switch outcome {
        case .success: return Self.submission(status: Self.successStatus())
        case .chainFailure: return Self.submission(status: Self.failureStatus())
        case .thrown: throw StubError.boom
        }
    }

    private static func submission(status: SubstrateExtrinsicStatus) -> ExtrinsicMonitorSubmission {
        ExtrinsicMonitorSubmission(
            extrinsicSubmittedModel: ExtrinsicSubmittedModel(
                txHash: "0x" + String(repeating: "0", count: 64),
                sender: .none
            ),
            status: status
        )
    }

    private static func successStatus() -> SubstrateExtrinsicStatus {
        .success(.init(
            extrinsicHash: "0x" + String(repeating: "0", count: 64),
            blockHash: "0x" + String(repeating: "1", count: 64),
            blockNumber: 1,
            extrinsicIndex: 0,
            interestedEvents: []
        ))
    }

    private static func failureStatus() -> SubstrateExtrinsicStatus {
        .failure(.init(
            extrinsicHash: "0x" + String(repeating: "0", count: 64),
            blockHash: "0x" + String(repeating: "1", count: 64),
            blockNumber: 1,
            extrinsicIndex: 0,
            error: .other(.init(module: "test", reason: "destroyed"))
        ))
    }
}

private final class StubLogger: SDKLoggerProtocol {
    func verbose(message _: String, file _: String, function _: String, line _: Int) {}
    func debug(message _: String, file _: String, function _: String, line _: Int) {}
    func info(message _: String, file _: String, function _: String, line _: Int) {}
    func warning(message _: String, file _: String, function _: String, line _: Int) {}
    func error(message _: String, file _: String, function _: String, line _: Int) {}
}
