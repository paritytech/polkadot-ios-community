import Foundation
import BigInt
import SubstrateSdk
import Individuality
import Operation_iOS
import ExtrinsicService
import KeyDerivation
import BandersnatchApi
import SubstrateOperation
import AsyncExtensions
import BackgroundExecution

@testable import Coinage

extension TransferSenderServiceTests {
    final class MockCoinService: CoinServiceProtocol, @unchecked Sendable {
        private let mutex = NSLock()
        private var _savedCoins: [Coin] = []
        private var _markedSpentIds: [String] = []
        private var _markedRecyclingIds: [String] = []
        private var _markedAvailableIds: [String] = []
        private var _markedPendingMintIds: [String] = []
        private var _markedHandedOffIds: [String] = []
        private var _markedPendingTransferIds: [String] = []
        private let callJournal: CallJournal?

        var savedCoins: [Coin] {
            mutex.withLock { _savedCoins }
        }

        var markedSpentIds: [String] {
            mutex.withLock { _markedSpentIds }
        }

        var markedRecyclingIds: [String] {
            mutex.withLock { _markedRecyclingIds }
        }

        var markedAvailableIds: [String] {
            mutex.withLock { _markedAvailableIds }
        }

        var markedPendingMintIds: [String] {
            mutex.withLock { _markedPendingMintIds }
        }

        var markedHandedOffIds: [String] {
            mutex.withLock { _markedHandedOffIds }
        }

        var markedPendingTransferIds: [String] {
            mutex.withLock { _markedPendingTransferIds }
        }

        init(callJournal: CallJournal? = nil) {
            self.callJournal = callJournal
        }

        func fetchAllCoins() async throws -> [Coin] { [] }

        func fetchAllTrackedCoins() async throws -> [TrackedCoin] { [] }

        func save(coins: [Coin]) async throws {
            callJournal?.record("insertOutputs")
            mutex.withLock { _savedCoins.append(contentsOf: coins) }
        }

        func markSpent(coinIds: [String]) async throws {
            mutex.withLock { _markedSpentIds.append(contentsOf: coinIds) }
        }

        func markRecycling(coinIds: [String]) async throws {
            mutex.withLock { _markedRecyclingIds.append(contentsOf: coinIds) }
        }

        func markAvailable(coinIds: [String]) async throws {
            mutex.withLock { _markedAvailableIds.append(contentsOf: coinIds) }
        }

        func markPendingTransfer(coinIds: [String]) async throws {
            callJournal?.record("reserve.coins")
            mutex.withLock { _markedPendingTransferIds.append(contentsOf: coinIds) }
        }

        func markPendingMint(coinIds: [String]) async throws {
            mutex.withLock { _markedPendingMintIds.append(contentsOf: coinIds) }
        }

        func markHandedOff(coinIds: [String]) async throws {
            callJournal?.record("handOff")
            mutex.withLock { _markedHandedOffIds.append(contentsOf: coinIds) }
        }
    }

    final class MockVoucherService: VoucherServiceProtocol, @unchecked Sendable {
        private let mutex = NSLock()
        private var _deletedIdentifiers: [String] = []
        private var _markedAvailableIds: [String] = []
        private var _markedPendingTransferIds: [String] = []
        private let callJournal: CallJournal?

        var deletedIdentifiers: [String] {
            mutex.withLock { _deletedIdentifiers }
        }

        var markedPendingTransferIds: [String] {
            mutex.withLock { _markedPendingTransferIds }
        }

        init(callJournal: CallJournal? = nil) {
            self.callJournal = callJournal
        }

        func load(
            amount _: BigUInt,
            externalAssetHolder _: any WalletManaging,
            breakdownContext _: DenominationBreakdownContext
        ) async throws {}

        func fetchAllTracked() async throws -> [TrackedVoucher] { [] }

        func fetchAll() async throws -> [Voucher] { [] }

        func fetchAvailableInRecycler() async throws -> [Coinage.Voucher] {
            []
        }

        func markPendingOnboarding(identifiers _: [String]) async throws {}

        func save(vouchers _: [Voucher]) async throws {}

        func markPendingTransfer(identifiers: [String]) async throws {
            callJournal?.record("reserve.vouchers")
            mutex.withLock { _markedPendingTransferIds.append(contentsOf: identifiers) }
        }

        func delete(identifiers: [String]) async throws {
            mutex.withLock { _deletedIdentifiers.append(contentsOf: identifiers) }
        }

        func markAvailable(identifiers: [String]) async throws {
            mutex.withLock { _markedAvailableIds.append(contentsOf: identifiers) }
        }
    }

    final class MockMemoBuilder: MemoBuilding {
        func buildMemo(
            from entries: [PlannedMemoEntry],
            breakdownContext: DenominationBreakdownContext
        ) throws -> TransferMemo {
            let totalValue = entries.reduce(BigUInt(0)) {
                $0 + breakdownContext.valueInPlanks(for: $1.valueExponent)
            }
            return TransferMemo(entries: entries.map { _ in Data([0x00]) }, totalValue: totalValue)
        }
    }

    /// Mock coin allocator that returns coins with sequential derivation indices
    actor MockCoinAllocator: CoinAllocating, CoinMinting {
        private var nextIndex: UInt64 = 100

        func allocate(exponent: Int16) async throws -> Coin {
            let index = nextIndex
            nextIndex += 1
            return Coin(exponent: exponent, derivationIndex: index, age: nil)
        }

        func mintCoin(exponent: Int16) async throws -> Coin {
            try await allocate(exponent: exponent)
        }
    }

    final class MockCoinKeyFactory: CoinKeyDeriving {
        typealias Model = Coin

        func derivePublicKey(for _: Coin) throws -> Data {
            Data(repeating: 0, count: 32)
        }

        func derivePrivateKey(for _: Coin) throws -> Data {
            Data(repeating: 0, count: 64)
        }
    }

    final class MockVoucherKeyFactory: VoucherKeyDeriving {
        typealias Model = Voucher

        func derivePublicKey(for _: Voucher) throws -> Data {
            Data(repeating: 0, count: 32)
        }

        func derivePrivateKey(for _: Voucher) throws -> Data {
            Data(repeating: 0, count: 64)
        }

        func createKeyManager(for model: Voucher) throws -> any BandersnatchKeyManaging {
            MockBandersnatchKeyManager(derivationIndex: model.derivationIndex)
        }
    }

    final class MockBandersnatchKeyManager: BandersnatchKeyManaging {
        let derivationIndex: UInt64

        init(derivationIndex: UInt64) {
            self.derivationIndex = derivationIndex
        }

        func getRawPublicKey() throws -> Data {
            Data(repeating: 0, count: 32)
        }

        func sign(_: Data) throws -> Data {
            Data(repeating: 0, count: 32)
        }

        func createProof(
            _: Data,
            members _: [BandersnatchPubKey],
            context _: Data,
            domainSize _: BandersnatchApi.RingDomainSize
        ) throws -> Data {
            Data(repeating: 0, count: 64)
        }

        func deriveAlias(for _: Data) throws -> Data {
            Data(repeating: 0, count: 32)
        }
    }

    /// Mock recycler loader that returns configured recycler states
    final class MockRecyclerLoader: RecyclerReadinessLoading {
        var states: [RecyclerKey: MembersPallet.RingStatus] = [:]
        var revisions: [RecyclerKey: UInt32] = [:]
        var maxConsolidationValue: UInt32 = 100

        func maxConsolidation() async throws -> UInt32 {
            maxConsolidationValue
        }

        func fetchRecyclerStates(for keys: [RecyclerKey]) async throws -> [RecyclerKey: MembersPallet.RingStatus] {
            var result: [RecyclerKey: MembersPallet.RingStatus] = [:]
            for key in keys {
                if let state = states[key] {
                    result[key] = state
                }
            }
            return result
        }

        func fetchRevisions(for keys: [RecyclerKey], blockHash _: BlockHashData?) async throws -> [
            RecyclerKey: UInt32
        ] {
            var result: [RecyclerKey: UInt32] = [:]
            for key in keys {
                if let revision = revisions[key] {
                    result[key] = revision
                }
            }
            return result
        }

        func subscribeRecyclerStates(
            for _: [RecyclerKey]
        ) -> AnyAsyncSequence<[RecyclerKey: MembersPallet.RingKeysStatus?]> {
            AsyncStream { _ in }.eraseToAnyAsyncSequence()
        }
    }

    /// Mock extrinsic submission monitor that simulates successful submissions
    final class MockExtrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol {
        func submitAndMonitorWrapper(
            extrinsicBuilderClosure _: @escaping ExtrinsicBuilderClosure,
            origin _: ExtrinsicOriginDefining,
            params _: ExtrinsicSubmissionParams
        ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
            .createWithResult(
                ExtrinsicMonitorSubmission(
                    extrinsicSubmittedModel: ExtrinsicSubmittedModel(
                        txHash: "0x" + String(repeating: "0", count: 64),
                        sender: .none
                    ),
                    status: .success(.init(
                        extrinsicHash: "0x" + String(repeating: "0", count: 64),
                        blockHash: "0x" + String(repeating: "1", count: 64),
                        blockNumber: 1,
                        extrinsicIndex: 0,
                        interestedEvents: []
                    ))
                )
            )
        }

        func submitAndMonitorWrapper(
            extrinsicBuilderClosure _: @escaping ExtrinsicBuilderIndexedClosure,
            origin _: ExtrinsicOriginDefining,
            indexes _: IndexSet,
            params _: ExtrinsicIndexedSubmissionParams
        ) -> CompoundOperationWrapper<ExtrinsicRetriableResult<ExtrinsicMonitorSubmission>> {
            .createWithError(TransferSenderServiceError.noSuitableCoins)
        }
    }

    /// Mock origin factory that returns mock origins
    final class MockOriginFactory: OriginCreating {
        let errorToThrow: Error?

        init(errorToThrow: Error? = nil) {
            self.errorToThrow = errorToThrow
        }

        func createAsCoinOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
            MockExtrinsicOrigin()
        }

        func createInfallibleUnpaidSignedOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
            MockExtrinsicOrigin()
        }

        func createAsUnloadTokenOrigins(
            voucherGroups: [[Voucher]],
            currentDate _: Date,
            blockHash _: SubstrateSdk.BlockHashData?
        ) async throws -> [ExtrinsicOriginDefining] {
            if let error = errorToThrow {
                throw error
            }
            return voucherGroups.map { _ in MockExtrinsicOrigin() }
        }
    }

    /// Mock extrinsic origin that returns successful resolution
    final class MockExtrinsicOrigin: ExtrinsicOriginDefining {
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

    final class MockBlockNumberProvider: BlockInfoProviding {
        func fetchCurrentHash() async throws -> SubstrateSdk.BlockHashData {
            Data(repeating: 0x00, count: 32)
        }

        func fetchCurrent() async throws -> BlockNumber {
            BlockNumber(123)
        }

        func fetchFinalized() async throws -> BlockNumber {
            BlockNumber(122)
        }

        func fetchFinalizedHash() async throws -> BlockHashData {
            Data(repeating: 0x00, count: 32)
        }

        func fetchBlockHash(_: BlockNumber) async throws -> BlockHashData {
            Data(repeating: 0x00, count: 32)
        }

        func subscribeFinalizedHeads() -> AnyAsyncSequence<Block.Header> {
            AsyncStream<Block.Header> { _ in }.eraseToAnyAsyncSequence()
        }

        func subscribeNewHeads() -> AnyAsyncSequence<Block.Header> {
            AsyncStream<Block.Header> { $0.finish() }.eraseToAnyAsyncSequence()
        }
    }

    /// Runs the operation inline, no OS background assertion — deterministic for tests.
    struct InlineBackgroundExecutor: BackgroundExecuting {
        func execute<T: Sendable>(
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            try await operation()
        }
    }
}
