import Foundation
import os
import Operation_iOS
import ExtrinsicService
import AsyncExtensions
@testable import Coinage

/// Thread-safe journal for recording mock call events.
final class CallJournal: @unchecked Sendable {
    private let mutex = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var events: [String] = []
    }

    func record(_ event: String) {
        mutex.withLock { $0.events.append(event) }
    }

    var events: [String] {
        mutex.withLock { $0.events }
    }
}

actor MockDurabilityService: DurabilityServicing {
    let store: MockDurabilityStore
    let callJournal: CallJournal

    private(set) var submittedInputs: [[DurabilityInput]] = []
    private(set) var submittedOutputs: [[OwnAsset]] = []
    private(set) var handoffAssets: [OwnAsset] = []
    private(set) var recoveryPassCount: Int = 0

    private let submissionOutcome: SubmissionOutcome

    enum SubmissionOutcome {
        /// Registration succeeds and the entry resolves to `finalizedSuccess`.
        case success
        /// Registration succeeds and the entry resolves to `failure`.
        case chainFailure
        /// `submit` throws before registering.
        case thrown
    }

    init(
        store: MockDurabilityStore = MockDurabilityStore(),
        callJournal: CallJournal = CallJournal(),
        submissionOutcome: SubmissionOutcome = .success
    ) {
        self.store = store
        self.callJournal = callJournal
        self.submissionOutcome = submissionOutcome
    }

    @discardableResult
    func submit(
        inputs: [DurabilityInput],
        outputs: [OwnAsset],
        builder _: @escaping ExtrinsicBuilderClosure,
        origin _: any ExtrinsicOriginDefining
    ) async throws -> TransactionId {
        submittedInputs.append(inputs)
        submittedOutputs.append(outputs)
        callJournal.record("submit")

        if case .thrown = submissionOutcome {
            throw StubError.boom
        }

        let entry = DurabilityEntry(
            inputs: inputs,
            outputs: outputs,
            checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
            mortality: 300
        )
        try await store.register(entry)

        // Drive the entry to a terminal status so a caller awaiting the outcome via
        // `subscribeTransactionStatus` resolves immediately.
        let terminal: EntryStatus =
            switch submissionOutcome {
            case .chainFailure: .failure
            case .success,
                 .thrown: .finalizedSuccess
            }
        try await store.updateStatus(entry.id, to: terminal)

        return entry.id
    }

    nonisolated func subscribeTransactionStatus(_ id: TransactionId) -> AnyAsyncSequence<EntryStatus> {
        store.subscribeStatus(of: id)
    }

    nonisolated func startRecoveryPass() {
        Task { [weak self] in
            await self?.incrementRecoveryPassCount()
        }
    }

    nonisolated func start() {}

    nonisolated func stop() {}

    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        callJournal.record("preCommitHandoff")
        handoffAssets.append(contentsOf: assets)
        try await store.markHandoffPending(assets)
        return StoreHandoffCommit(assets: assets, store: store)
    }

    func releaseUncommittedHandoffs() async throws {
        try await store.releaseUncommittedHandoffs()
    }

    private func incrementRecoveryPassCount() {
        recoveryPassCount += 1
    }
}

enum StubError: Error {
    case boom
}
