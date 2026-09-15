import AsyncExtensions
import BigInt
import DurableTransactions
import ExtrinsicService
import Foundation
import Individuality
import KeyDerivation
import os
import SubstrateSdk
@testable import Coinage

// MARK: - Installations

/// An in-memory ``CoinageInstallationRepositoryProtocol`` with a fixed current installation.
final class InMemoryInstallations: CoinageInstallationRepositoryProtocol, @unchecked Sendable {
    private let current: CoinageInstallationId
    private let state = OSAllocatedUnfairLock<[CoinageInstallationId: PreviousInstallation]>(initialState: [:])
    private let order = OSAllocatedUnfairLock<[CoinageInstallationId]>(initialState: [])

    init(current: CoinageInstallationId = .test) {
        self.current = current
    }

    func previous(_ id: CoinageInstallationId) -> PreviousInstallation? {
        state.withLock { $0[id] }
    }

    func getOrCreateCurrent() async throws -> CoinageInstallationId { current }

    func addPrevious(_ installations: [CoinageInstallationId]) async throws {
        for installation in installations where installation != current {
            let added = state.withLock { previous -> Bool in
                guard previous[installation] == nil else { return false }
                previous[installation] = PreviousInstallation(
                    id: installation, coinScanNextIndex: 0, voucherScanNextIndex: 0, initialScanCompleted: false
                )
                return true
            }
            if added { order.withLock { $0.append(installation) } }
        }
    }

    func getPrevious() async throws -> [PreviousInstallation] {
        let ids = order.withLock { $0 }
        return state.withLock { previous in ids.compactMap { previous[$0] } }
    }

    func updateCoinScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws {
        update(installation) { $0.changing(coinScanNextIndex: nextIndex) }
    }

    func updateVoucherScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws {
        update(installation) { $0.changing(voucherScanNextIndex: nextIndex) }
    }

    func markInitialScanCompleted(_ installation: CoinageInstallationId) async throws {
        update(installation) { $0.changing(initialScanCompleted: true) }
    }

    private func update(
        _ installation: CoinageInstallationId,
        _ change: (PreviousInstallation) -> PreviousInstallation
    ) {
        state.withLock { previous in
            guard let existing = previous[installation] else { return }
            previous[installation] = change(existing)
        }
    }
}

extension PreviousInstallation {
    func changing(
        coinScanNextIndex: UInt32? = nil,
        voucherScanNextIndex: UInt32? = nil,
        initialScanCompleted: Bool? = nil
    ) -> PreviousInstallation {
        PreviousInstallation(
            id: id,
            coinScanNextIndex: coinScanNextIndex ?? self.coinScanNextIndex,
            voucherScanNextIndex: voucherScanNextIndex ?? self.voucherScanNextIndex,
            initialScanCompleted: initialScanCompleted ?? self.initialScanCompleted
        )
    }
}

// MARK: - Config

final class StubDataStoreConfig: AccountDataStoreConfigProviding, @unchecked Sendable {
    private let address = OSAllocatedUnfairLock<Data?>(initialState: nil)

    init(contract: Data? = TestContracts.contract) {
        address.withLock { $0 = contract }
    }

    var contract: Data? {
        get { address.withLock { $0 } }
        set { address.withLock { $0 = newValue } }
    }

    func contractAddress() async -> Data? { contract }
}

enum TestContracts {
    static let contract = Data(repeating: 0x0C, count: 20)
    static let otherContract = Data(repeating: 0x0D, count: 20)
}

// MARK: - Data store

/// Registered installations per (contract, block hash); a read of an unlisted pair fails.
final class StubDataStoreRepository: AccountDataStoreRepositoryProtocol, @unchecked Sendable {
    struct Key: Hashable {
        let contract: Data
        let blockHash: Data?
    }

    private let lists = OSAllocatedUnfairLock<[Key: Result<Set<CoinageInstallationId>, Error>]>(initialState: [:])
    private let readCount = OSAllocatedUnfairLock(initialState: 0)
    private let registrationInput = OSAllocatedUnfairLock<Data>(initialState: Data([0xE5, 0x61, 0x86, 0x8D]))
    var account = DataStoreAccount(
        privateKey: Data(repeating: 0x0A, count: 64),
        publicKey: Data(repeating: 0x0A, count: 32),
        evmAccountId: Data(repeating: 0x0E, count: 20),
        encryptionKey: Data(repeating: 0, count: 32)
    )

    var reads: Int { readCount.withLock { $0 } }

    func listed(
        _ installations: Set<CoinageInstallationId>,
        contract: Data = TestContracts.contract,
        at blockHash: Data? = nil
    ) {
        lists.withLock { $0[Key(contract: contract, blockHash: blockHash)] = .success(installations) }
    }

    func failing(
        contract: Data = TestContracts.contract,
        at blockHash: Data? = nil,
        error: Error = InstallationStubError.unreachable
    ) {
        lists.withLock { $0[Key(contract: contract, blockHash: blockHash)] = .failure(error) }
    }

    func fetchRegisteredInstallations(contract: Data, at blockHash: Data?) async throws -> Set<CoinageInstallationId> {
        readCount.withLock { $0 += 1 }
        guard let result = lists.withLock({ $0[Key(contract: contract, blockHash: blockHash)] }) else {
            throw InstallationStubError.unreachable
        }
        return try result.get()
    }

    func registrationCall(target: InstallationRegistrationTarget) async throws -> InstallationRegistrationCall {
        InstallationRegistrationCall(
            account: account,
            contract: target.contract,
            input: registrationInput.withLock { $0 }
        )
    }
}

enum InstallationStubError: Error, Equatable {
    case unreachable
    case notEnoughPgas
    case nodeWentAway
}

// MARK: - Engine

/// Emits like the store: every write re-emits, identical or not, and a subscriber first sees the
/// current rows.
final class FakeRegistrationEngine: DurableTxServicing, @unchecked Sendable {
    let oracles = TxCompletionOracleRegistry()

    private struct State {
        var groups: [DurableTxGroupId: [DurableTxEntry]] = [:]
        var observers: [DurableTxGroupId: [AsyncStream<[DurableTxEntry]>.Continuation]] = [:]
        var recoveryStarts = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var recoveryStarts: Int { state.withLock { $0.recoveryStarts } }

    func current(_ group: DurableTxGroupId) -> [DurableTxEntry] {
        state.withLock { $0.groups[group] ?? [] }
    }

    func set(_ entries: [DurableTxEntry], group: DurableTxGroupId) {
        let observers = state.withLock { state -> [AsyncStream<[DurableTxEntry]>.Continuation] in
            state.groups[group] = entries
            return state.observers[group] ?? []
        }
        observers.forEach { $0.yield(entries) }
    }

    func reEmit(group: DurableTxGroupId) {
        set(current(group), group: group)
    }

    func submitTransactions(
        domain _: TxDomainId,
        requests _: [DurableTxRequest],
        groupId _: DurableTxGroupId?,
        onRegister _: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        fatalError("the registrar submits through its submitter")
    }

    func subscribeTransactionStatus(_: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        AsyncStream<DurableTxStatus> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func getGroupEntries(domain _: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry] {
        current(groupId)
    }

    func subscribeGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) -> AnyAsyncSequence<[DurableTxEntry]> {
        precondition(domain == .coinageInstallation)
        return AsyncStream<[DurableTxEntry]> { continuation in
            let snapshot = state.withLock { state -> [DurableTxEntry] in
                state.observers[groupId, default: []].append(continuation)
                return state.groups[groupId] ?? []
            }
            continuation.yield(snapshot)
        }
        .eraseToAnyAsyncSequence()
    }

    func startRecoveryPass() {
        state.withLock { $0.recoveryStarts += 1 }
    }

    func start() {}

    func stop() {}
}

extension DurableTxEntry {
    static func registration(
        _ target: InstallationRegistrationTarget,
        id: DurableTxId = UUID(),
        status: DurableTxStatus
    ) -> DurableTxEntry {
        .fixture(id: id, domainId: .coinageInstallation, status: status, groupId: target.registrationGroup)
    }

    func changing(status: DurableTxStatus) -> DurableTxEntry {
        .fixture(
            id: id,
            domainId: domainId,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status,
            groupId: groupId,
            txHash: txHash
        )
    }
}

// MARK: - Submitter

/// An accepted attempt shows up as a fresh pending row in its target's group; a gate holds it before it
/// commits.
final class FakeRegistrationSubmitter: InstallationRegistrationSubmitting, @unchecked Sendable {
    private let engine: FakeRegistrationEngine
    private let state = OSAllocatedUnfairLock<(attempts: [InstallationRegistrationTarget], failNext: Int)>(
        initialState: ([], 0)
    )
    private let gate = OSAllocatedUnfairLock<AsyncStream<Void>.Continuation?>(initialState: nil)
    private let gateStream: AsyncStream<Void>
    private var gated = false

    init(engine: FakeRegistrationEngine) {
        self.engine = engine
        var continuation: AsyncStream<Void>.Continuation?
        gateStream = AsyncStream<Void> { continuation = $0 }
        gate.withLock { $0 = continuation }
    }

    var attempts: [InstallationRegistrationTarget] { state.withLock { $0.attempts } }

    func failNextAttempts(_ count: Int) {
        state.withLock { $0.failNext = count }
    }

    /// Holds every attempt at its start until ``openGate()``.
    func holdAttempts() {
        gated = true
    }

    func openGate() {
        gated = false
        gate.withLock { $0?.yield(()) }
    }

    func submitAttempt(target: InstallationRegistrationTarget) async throws -> DurableTxId {
        state.withLock { $0.attempts.append(target) }

        if gated {
            for await _ in gateStream {
                break
            }
        }

        let shouldFail = state.withLock { state -> Bool in
            guard state.failNext > 0 else { return false }
            state.failNext -= 1
            return true
        }
        if shouldFail { throw InstallationStubError.notEnoughPgas }

        let entry = DurableTxEntry.registration(target, status: .pending)
        engine.set(engine.current(target.registrationGroup) + [entry], group: target.registrationGroup)
        return entry.id
    }
}

// MARK: - Revive / PGAS / fee

final class StubReviveApi: ReviveContractApiProtocol, @unchecked Sendable {
    var mapped = true
    var dryRunResult: Result<ReviveDryRun, Error> = .success(
        ReviveDryRun(
            data: Data(),
            weightRequired: Substrate.WeightV2(refTime: 1_000_000, proofSize: 70_000),
            storageDeposit: 413_000_000
        )
    )
    private(set) var dryRuns: [(origin: AccountId, contract: Data, input: Data)] = []
    private(set) var mappingChecks: [AccountId] = []

    func callReadOnly(contract _: Data, input _: Data, at _: Data?) async throws -> Data { Data() }

    func dryRun(origin: AccountId, contract: Data, input: Data) async throws -> ReviveDryRun {
        dryRuns.append((origin, contract, input))
        return try dryRunResult.get()
    }

    func isAccountMapped(_ account: AccountId) async throws -> Bool {
        mappingChecks.append(account)
        return mapped
    }
}

final class StubPgasProvisioner: PGASAccountProvisioning, @unchecked Sendable {
    var fundingError: Error?
    var coverError: Error?
    private(set) var funded: [AccountId] = []
    private(set) var covered: [(account: AccountId, required: BigUInt)] = []

    func ensureFunded(account: AccountId) async throws {
        funded.append(account)
        if let fundingError { throw fundingError }
    }

    func ensureCovers(account: AccountId, required: BigUInt) async throws {
        covered.append((account, required))
        if let coverError { throw coverError }
    }
}

final class StubFeeEstimator: RegistrationFeeEstimating, @unchecked Sendable {
    var fee: BigUInt = 30_000_000
    private(set) var estimates = 0

    func estimateFee(
        _: @escaping ExtrinsicBuilderClosure,
        origin _: any ExtrinsicOriginDefining
    ) async throws -> BigUInt {
        estimates += 1
        return fee
    }
}

struct StubReviveCallArguments: ReviveCallArgumentsProviding {
    var name = "weight_limit"

    func weightLimitArgumentName() async throws -> String { name }
}

/// Records what the submitter hands to the engine.
final class RecordingEngine: DurableTxServicing, @unchecked Sendable {
    let oracles = TxCompletionOracleRegistry()
    private(set) var submissions: [(domain: TxDomainId, requests: Int, groupId: DurableTxGroupId?)] = []
    let submittedId = UUID()

    func submitTransactions(
        domain: TxDomainId,
        requests: [DurableTxRequest],
        groupId: DurableTxGroupId?,
        onRegister _: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        submissions.append((domain, requests.count, groupId))
        return [submittedId]
    }

    func subscribeTransactionStatus(_: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        AsyncStream<DurableTxStatus> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func getGroupEntries(domain _: TxDomainId, groupId _: DurableTxGroupId) async throws -> [DurableTxEntry] { [] }

    func subscribeGroupEntries(
        domain _: TxDomainId,
        groupId _: DurableTxGroupId
    ) -> AnyAsyncSequence<[DurableTxEntry]> {
        AsyncStream<[DurableTxEntry]> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func startRecoveryPass() {}
    func start() {}
    func stop() {}
}

/// Only the signed origin is needed by the registration suites.
final class StubSignedOriginFactory: OriginCreating {
    private(set) var signedOrigins: [ChainId] = []

    func createAsCoinOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining { StubExtrinsicOrigin() }

    func createSignedOrigin(for _: WalletManaging, chainId: ChainId) async throws -> ExtrinsicOriginDefining {
        signedOrigins.append(chainId)
        return StubExtrinsicOrigin()
    }

    func createInfallibleUnpaidSignedOrigin(for _: WalletManaging) throws -> ExtrinsicOriginDefining {
        StubExtrinsicOrigin()
    }

    func createAsUnloadTokenOrigins(
        voucherGroups _: [[Voucher]],
        currentDate _: Date,
        blockHash _: BlockHashData?
    ) async throws -> [ExtrinsicOriginDefining] {
        []
    }
}
