import Testing
import Foundation
import Operation_iOS
import ExtrinsicService
import KeyDerivation
import BandersnatchApi
import BackgroundExecution
import SubstrateSdk
import SDKLogger
@testable import Coinage

/// `CoinageRecyclingService` is submission-only: the decision of *which* coins to recycle lives in
/// `CoinRecyclingEvaluator`. These tests pin the submission contract — one `loadRecyclerWithCoin`
/// entry per coin, consuming that coin and minting a voucher — and that a pre-submission failure
/// surfaces with nothing registered.
@Suite("CoinageRecyclingService Tests")
struct CoinageRecyclingServiceTests {
    @Test("No coins is a no-op")
    func emptyIsNoOp() async throws {
        let sut = makeSUT()

        try await sut.service.recycleCoins([])

        #expect(await sut.txService.submittedInputs.isEmpty)
    }

    @Test("Each coin registers one entry consuming it and minting a voucher")
    func eachCoinRegistersOneEntry() async throws {
        let sut = makeSUT()

        try await sut.service.recycleCoins([coin(index: 7), coin(index: 9)])

        let inputs = await sut.txService.submittedInputs
        let outputs = await sut.txService.submittedOutputs
        #expect(inputs == [[.coin(.own(7, key(7)))], [.coin(.own(9, key(9)))]])
        #expect(outputs.allSatisfy { $0.count == 1 })
    }

    @Test("Coins are submitted in the order given")
    func preservesOrder() async throws {
        let sut = makeSUT()

        try await sut.service.recycleCoins([coin(index: 3), coin(index: 1), coin(index: 2)])

        let inputs = await sut.txService.submittedInputs
        #expect(inputs == [[.coin(.own(3, key(3)))], [.coin(.own(1, key(1)))], [.coin(.own(2, key(2)))]])
    }

    @Test("A coin whose preparation fails is skipped, not rethrown, and nothing is submitted")
    func prepareFailureIsSkipped() async throws {
        let sut = makeSUT(minterError: StubError.boom)

        try await sut.service.recycleCoins([coin(index: 7)])

        #expect(await sut.txService.submittedInputs.isEmpty)
    }
}

// MARK: - SUT

private extension CoinageRecyclingServiceTests {
    struct SUT {
        let service: CoinageRecyclingService
        let txService: MockCoinageTxService
    }

    func makeSUT(minterError: Error? = nil) -> SUT {
        let txService = MockCoinageTxService()
        let service = CoinageRecyclingService(
            voucherMinter: StubVoucherMinter(error: minterError),
            coinKeypairFactory: StubCoinKeyFactory(),
            voucherKeypairFactory: StubVoucherKeyFactory(),
            txService: txService,
            originFactory: StubOriginFactory(),
            backgroundExecutor: StubBackgroundExecutor(),
            logger: StubLogger()
        )
        return SUT(service: service, txService: txService)
    }

    func key(_ index: DerivationIndex) -> Data {
        Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
    }

    func coin(index: DerivationIndex) -> Coin {
        Coin(exponent: 3, derivationIndex: index, age: 14, isOnchain: true, publicKey: key(index))
    }
}

// MARK: - Stubs

private func stubKey(_ index: DerivationIndex) -> Data {
    Data(repeating: UInt8(truncatingIfNeeded: index), count: 32)
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
            publicKey: stubKey(index)
        )
    }
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

private struct StubBackgroundExecutor: BackgroundExecuting {
    func execute<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}

private final class StubLogger: SDKLoggerProtocol {
    func verbose(message _: String, file _: String, function _: String, line _: Int) {}
    func debug(message _: String, file _: String, function _: String, line _: Int) {}
    func info(message _: String, file _: String, function _: String, line _: Int) {}
    func warning(message _: String, file _: String, function _: String, line _: Int) {}
    func error(message _: String, file _: String, function _: String, line _: Int) {}
}
