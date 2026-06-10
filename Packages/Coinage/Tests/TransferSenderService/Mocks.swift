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

@testable import Coinage

extension TransferSenderServiceTests {
    final class MockCoinService: CoinServiceProtocol, @unchecked Sendable {
        private let mutex = NSLock()
        private var _savedCoins: [Coin] = []
        private var _markedSpentIds: [String] = []
        private var _markedRecyclingIds: [String] = []
        private var _markedAvailableIds: [String] = []

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

        func fetchAllCoins() async throws -> [Coin] { [] }

        func save(coins: [Coin]) async throws {
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

        func markPendingTransfer(coinIds _: [String]) async throws {}
    }

    final class MockVoucherService: VoucherServiceProtocol, @unchecked Sendable {
        private let mutex = NSLock()
        private var _deletedIdentifiers: [String] = []
        private var _markedAvailableIds: [String] = []

        var deletedIdentifiers: [String] {
            mutex.withLock { _deletedIdentifiers }
        }

        func load(
            amount _: BigUInt,
            externalAssetHolder _: any WalletManaging,
            breakdownContext _: DenominationBreakdownContext
        ) async throws {}

        func fetchAll() async throws -> [Voucher] { [] }

        func fetchAvailableInRecycler() async throws -> [Coinage.Voucher] {
            []
        }

        func markPendingOnboarding(identifiers _: [String]) async throws {}

        func save(vouchers _: [Voucher]) async throws {}

        func markPendingTransfer(identifiers _: [String]) async throws {}

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
    actor MockCoinAllocator: CoinAllocating {
        private var nextIndex: UInt32 = 100

        func allocate(exponent: Int16) async throws -> Coin {
            let index = nextIndex
            nextIndex += 1
            return Coin(exponent: exponent, derivationIndex: index, age: nil)
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
        let derivationIndex: UInt32

        init(derivationIndex: UInt32) {
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
            voucherGroups.map { _ in MockExtrinsicOrigin() }
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

    /// Mock transfer WAL store
    actor MockTransferWALStore: TransferWALStoring {
        func save(_: TransferWALEntry) async throws {}

        func update(id _: UUID, checkpointBlock _: Coinage.CheckpointBlock) async throws {}

        func fetchAll() async throws -> [TransferWALEntry] { [] }

        func save(contentsOf _: [TransferWALEntry]) async throws {}

        func delete(id _: UUID) async throws {}
    }

    /// Mock extrinsic submission coordinator
    final class MockExtrinsicSubmissionCoordinator: ExtrinsicSubmissionCoordinating {
        var result: ExtrinsicMonitorSubmission
        var error: Error?

        init() {
            result = ExtrinsicMonitorSubmission(
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
        }

        func submit(
            walEntryId _: UUID,
            builder _: @escaping ExtrinsicBuilderClosure,
            origin _: any ExtrinsicOriginDefining
        ) async throws -> ExtrinsicMonitorSubmission {
            if let error { throw error }
            return result
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
    }
}
