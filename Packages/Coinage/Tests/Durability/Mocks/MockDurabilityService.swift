import Foundation
import os
import Operation_iOS
import ExtrinsicService
import Coinage

/// Thread-safe journal for recording mock call events.
final class CallJournal: @unchecked Sendable {
    private let mutex = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var events: [String] = []
        var abandonedIds: Set<String> = []
    }

    func record(_ event: String) {
        mutex.withLock { $0.events.append(event) }
    }

    var events: [String] {
        mutex.withLock { $0.events }
    }

    func recordAbandoned(_ id: TransactionId) {
        mutex.withLock { $0.abandonedIds.insert(id.uuidString) }
    }

    var abandonedIds: Set<String> {
        mutex.withLock { $0.abandonedIds }
    }
}

actor MockDurabilityService: DurabilityServicing {
    let store: MockDurabilityStore
    let callJournal: CallJournal

    private(set) var submittedInputs: [[Input]] = []
    private(set) var submittedOutputs: [[OwnAsset]] = []
    private(set) var recoveryPassCount: Int = 0

    private let submissionOutcome: SubmissionOutcome
    private let submissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol

    enum SubmissionOutcome {
        case success
        case chainFailure
        case thrown
    }

    init(
        store: MockDurabilityStore = MockDurabilityStore(),
        callJournal: CallJournal = CallJournal(),
        submissionOutcome: SubmissionOutcome = .success,
        submissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol = MockExtrinsicSubmitMonitor()
    ) {
        self.store = store
        self.callJournal = callJournal
        self.submissionOutcome = submissionOutcome
        self.submissionMonitor = submissionMonitor
    }

    func submit(
        inputs: [Input],
        outputs: [OwnAsset],
        builder: @escaping ExtrinsicBuilderClosure,
        origin: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission {
        let id = try await register(inputs: inputs, outputs: outputs)
        return try await submitRegistered(entryId: id, builder: builder, origin: origin)
    }

    func register(inputs: [Input], outputs: [OwnAsset]) async throws -> TransactionId {
        submittedInputs.append(inputs)
        submittedOutputs.append(outputs)
        callJournal.record("register")
        let entry = DurabilityEntry(
            inputs: inputs,
            outputs: outputs,
            checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
            mortality: 300
        )
        try await store.register(entry)
        return entry.id
    }

    func submitRegistered(
        entryId: TransactionId,
        builder _: @escaping ExtrinsicBuilderClosure,
        origin _: any ExtrinsicOriginDefining
    ) async throws -> DurabilitySubmission {
        callJournal.record("submitRegistered")
        let submission = try await createSubmission(for: submissionOutcome)
        return DurabilitySubmission(transactionId: entryId, submission: submission)
    }

    nonisolated func abandon(_ id: TransactionId) {
        callJournal.record("abandon(\(id))")
        callJournal.recordAbandoned(id)
    }

    nonisolated func startRecoveryPass() {
        Task { [weak self] in
            await self?.incrementRecoveryPassCount()
        }
    }

    nonisolated func start() {}

    nonisolated func stop() {}

    func transactionStatus(_ id: TransactionId) async throws -> EntryStatus {
        guard let entry = try await store.fetch(id: id) else {
            throw DurabilityError.entryNotFound(id)
        }
        return entry.status
    }

    func registerHandoff(_ coin: OwnAsset) async throws {
        try await store.markHandedOff(coin)
    }

    func assetStatus(_ asset: OwnAsset) async throws -> CoinageAssetState {
        try await assetStatuses([asset])[asset]
            ?? CoinageAssetState(lock: .idle, minterStatus: nil)
    }

    func assetStatuses(_ assets: [OwnAsset]) async throws -> [OwnAsset: CoinageAssetState] {
        guard !assets.isEmpty else { return [:] }

        let handedOff = try await store.handedOffIdentifiers()
        let live = try await store.fetchLive()
        let reservedInputs = live.inputIdentifiers()
        let allEntries = try await store.fetchAll()

        var mintersByOutput: [String: EntryStatus] = [:]
        for entry in allEntries {
            for output in entry.outputs {
                mintersByOutput[output.identifier] = entry.status
            }
        }

        return assets.reduce(into: [:]) { result, asset in
            let identifier = asset.identifier
            let lock: AssetStatus =
                if handedOff.contains(identifier) {
                    .handedOff
                } else if reservedInputs.contains(identifier) {
                    .reserved
                } else {
                    .idle
                }
            result[asset] = CoinageAssetState(lock: lock, minterStatus: mintersByOutput[identifier])
        }
    }

    func paymentStatus(of _: OwnAsset) async throws -> CoinPaymentStatus {
        .detecting
    }

    private func createSubmission(
        for outcome: SubmissionOutcome
    ) async throws -> ExtrinsicMonitorSubmission {
        switch outcome {
        case .success:
            return StubSubmission.make(status: StubSubmission.success)
        case .chainFailure:
            return StubSubmission.make(status: StubSubmission.failure)
        case .thrown:
            throw StubError.boom
        }
    }

    private func incrementRecoveryPassCount() {
        recoveryPassCount += 1
    }
}

enum StubError: Error {
    case boom
}

/// Canned extrinsic submissions shared by the mocks in this file.
private enum StubSubmission {
    static let txHash = "0x" + String(repeating: "0", count: 64)
    static let blockHash = "0x" + String(repeating: "1", count: 64)

    static var success: SubstrateExtrinsicStatus {
        .success(.init(
            extrinsicHash: txHash,
            blockHash: blockHash,
            blockNumber: 1,
            extrinsicIndex: 0,
            interestedEvents: []
        ))
    }

    static var failure: SubstrateExtrinsicStatus {
        .failure(.init(
            extrinsicHash: txHash,
            blockHash: blockHash,
            blockNumber: 1,
            extrinsicIndex: 0,
            error: .other(.init(module: "test", reason: "destroyed"))
        ))
    }

    static func make(status: SubstrateExtrinsicStatus) -> ExtrinsicMonitorSubmission {
        ExtrinsicMonitorSubmission(
            extrinsicSubmittedModel: ExtrinsicSubmittedModel(txHash: txHash, sender: .none),
            status: status
        )
    }
}

private final class MockExtrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol {
    func submitAndMonitorWrapper(
        extrinsicBuilderClosure _: @escaping ExtrinsicBuilderClosure,
        origin _: ExtrinsicOriginDefining,
        params _: ExtrinsicSubmissionParams
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        .createWithResult(StubSubmission.make(status: StubSubmission.success))
    }

    func submitAndMonitorWrapper(
        extrinsicBuilderClosure _: @escaping ExtrinsicBuilderIndexedClosure,
        origin _: ExtrinsicOriginDefining,
        indexes _: IndexSet,
        params _: ExtrinsicIndexedSubmissionParams
    ) -> CompoundOperationWrapper<ExtrinsicRetriableResult<ExtrinsicMonitorSubmission>> {
        .createWithError(StubError.boom)
    }
}
