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

    @Test("Only free, on-chain coins at or above the recycle age are submitted")
    func recyclesOnlyEligibleCoins() async throws {
        let sut = makeSUT(coins: [
            makeTracked(index: 1, age: 13),
            makeTracked(index: 2, age: 14),
            makeTracked(index: 3, age: 16)
        ])

        await sut.service.recycleOldCoins()

        // Eligible are 2 and 3, processed oldest first (3 then 2).
        let inputs = await sut.durabilityService.store.allEntries.flatMap(\.inputs)
        #expect(inputs == [.coin(.own(3, testKey(3))), .coin(.own(2, testKey(2)))])
    }

    @Test("Coins below the age, with unknown age, or not free/on-chain are skipped")
    func skipsIneligible() async throws {
        let sut = makeSUT(coins: [
            makeTracked(index: 1, age: 16),
            makeTracked(index: 2, age: 16, free: false),
            makeTracked(index: 3, age: 16, onchain: false),
            makeTracked(index: 4, age: nil)
        ])

        await sut.service.recycleOldCoins()

        let inputs = await sut.durabilityService.store.allEntries.flatMap(\.inputs)
        #expect(inputs == [.coin(.own(1, testKey(1)))])
    }

    @Test("Eligible coins are processed oldest first")
    func processesOldestFirst() async throws {
        let sut = makeSUT(coins: [
            makeTracked(index: 1, age: 14),
            makeTracked(index: 2, age: 16),
            makeTracked(index: 3, age: 15)
        ])

        await sut.service.recycleOldCoins()

        let inputs = await sut.durabilityService.store.allEntries.flatMap(\.inputs)
        #expect(inputs == [.coin(.own(2, testKey(2))), .coin(.own(3, testKey(3))), .coin(.own(1, testKey(1)))])
    }

    // MARK: - Submission

    @Test("A recycle registers one entry consuming the coin and minting a voucher")
    func successRegistersEntry() async throws {
        let sut = makeSUT(coins: [makeTracked(index: 7, age: 14)])

        await sut.service.recycleOldCoins()

        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
        #expect(entries.first?.inputs == [.coin(.own(7, testKey(7)))])
        #expect(entries.first?.outputs.count == 1)
    }

    @Test("A pre-submission mint failure registers no entry")
    func mintErrorRegistersNoEntry() async throws {
        let sut = makeSUT(coins: [makeTracked(index: 7, age: 14)], minterError: StubError.boom)

        await sut.service.recycleOldCoins()

        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.isEmpty)
    }

    @Test("recycleCoins rethrows on a pre-submission failure")
    func recycleCoinsRethrows() async throws {
        let sut = makeSUT(minterError: StubError.boom)

        await #expect(throws: StubError.self) {
            try await sut.service.recycleCoins([makeTracked(index: 7, age: 14).coin])
        }
    }

    // MARK: - Scheduling

    @Test("scheduleRecycling arms the background task and recycles")
    func scheduleRecyclingArmsAndRecycles() async throws {
        let sut = makeSUT(coins: [makeTracked(index: 1, age: 14)], backgroundRecyclingInterval: 3_600)

        await sut.service.scheduleRecycling()

        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
        #expect(await sut.scheduler.scheduleCount == 1)
        #expect(await sut.scheduler.lastEarliestBegin == 3_600)
    }

    @Test("Foreground recycling recycles without arming a background task")
    func foregroundRecyclingRuns() async throws {
        let sut = makeSUT(coins: [makeTracked(index: 1, age: 14)])

        await sut.service.recycleOldCoins()

        let entries = await sut.durabilityService.store.allEntries
        #expect(entries.count == 1)
        #expect(await sut.scheduler.scheduleCount == 0)
    }
}

// MARK: - SUT

private extension CoinageRecyclingServiceTests {
    struct SUT {
        let service: CoinageRecyclingService
        let coinService: RecyclingMockCoinService
        let scheduler: RecordingScheduler
        let durabilityService: MockCoinageTxService
    }

    func makeSUT(
        coins: [TrackedCoin] = [],
        minterError: Error? = nil,
        backgroundRecyclingInterval: TimeInterval = 3_600,
        recycleAtAge: Int16 = 14
    ) -> SUT {
        let coinService = RecyclingMockCoinService(trackedCoins: coins)
        let scheduler = RecordingScheduler()
        let durabilityService = MockCoinageTxService()

        let service = CoinageRecyclingService(
            schedulerFactory: RecordingSchedulerFactory(scheduler: scheduler),
            coinService: coinService,
            voucherMinter: StubVoucherMinter(error: minterError),
            coinKeypairFactory: StubCoinKeyFactory(),
            voucherKeypairFactory: StubVoucherKeyFactory(),
            txService: durabilityService,
            originFactory: StubOriginFactory(),
            logger: StubLogger(),
            backgroundRecyclingInterval: backgroundRecyclingInterval,
            recycleAtAge: recycleAtAge
        )

        return SUT(
            service: service,
            coinService: coinService,
            scheduler: scheduler,
            durabilityService: durabilityService
        )
    }

    func makeTracked(index: UInt64, age: Int16?, free: Bool = true, onchain: Bool = true) -> TrackedCoin {
        let coin = Coin(
            exponent: 3,
            derivationIndex: index,
            age: age,
            isOnchain: onchain,
            publicKey: testKey(index)
        )
        let state = free
            ? CoinageAssetState(handedOff: false, consumerStatus: nil, minterStatus: nil)
            : CoinageAssetState(handedOff: false, consumerStatus: .finalizedSuccess, minterStatus: nil)
        return TrackedCoin(coin: coin, state: state)
    }
}

// MARK: - Mocks

private final class RecyclingMockCoinService: CoinServiceProtocol, @unchecked Sendable {
    private let trackedCoins: [TrackedCoin]

    init(trackedCoins: [TrackedCoin]) {
        self.trackedCoins = trackedCoins
    }

    func fetchAllCoins() async throws -> [Coin] { trackedCoins.map(\.coin) }
    func fetchAllTrackedCoins() async throws -> [TrackedCoin] { trackedCoins }
    func save(coins _: [Coin]) async throws {}
}

private actor StubVoucherMinter: VoucherMinting {
    private var nextIndex: UInt64 = 500
    private let error: Error?

    init(error: Error?) {
        self.error = error
    }

    func mintVoucher(exponent: Int16) async throws -> Voucher {
        if let error { throw error }
        let index = nextIndex
        nextIndex += 1
        return Voucher(
            exponent: exponent,
            derivationIndex: index,
            allocatedAt: Date(),
            readyAt: Date.distantPast,
            remoteState: .unlocated,
            publicKey: testKey(index)
        )
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

private final class StubCoinKeyFactory: CoinKeyDeriving {
    func derivePublicKey(index _: DerivationIndex) throws -> PublicKey { Data(repeating: 0, count: 32) }
    func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey { Data(repeating: 0, count: 64) }
}

private final class StubVoucherKeyFactory: VoucherKeyDeriving {
    func derivePublicKey(index _: DerivationIndex) throws -> PublicKey { Data(repeating: 0, count: 32) }
    func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey { Data(repeating: 0, count: 64) }

    func createKeyManager(index _: DerivationIndex) throws -> any BandersnatchKeyManaging {
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
