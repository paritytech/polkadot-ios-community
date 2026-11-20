import AsyncExtensions
import DurableTransactions
import DurableTransactionsTestSupport

/// Schedules through the in-memory store that the engine's async path writes through, so a scheduled
/// registration commits or rolls back as it does in production. The rest of the engine is not exercised here.
final class StoreSchedulingEngine: DurableTxServicing, @unchecked Sendable {
    private let store: InMemoryDurableTxRepository

    init(store: InMemoryDurableTxRepository) {
        self.store = store
    }

    func schedule(
        domain: TxDomainId,
        groupId: DurableTxGroupId?,
        policies: [SubmissionPolicy],
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        let schedules = policies.map { DurableTxSchedule(domainId: domain, groupId: groupId, policy: $0) }
        return try await store.schedule(schedules, in: nil, onRegister: onRegister)
    }

    func submitTransactions(
        domain _: TxDomainId,
        requests _: [DurableTxRequest],
        groupId _: DurableTxGroupId?,
        policies _: [SubmissionPolicy?],
        onRegister _: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        fatalError("these cases only schedule")
    }

    func schedule(
        domain _: TxDomainId,
        groupId _: DurableTxGroupId?,
        policies _: [SubmissionPolicy],
        joining _: any DurableTxRegistrationScope,
        onRegister _: DurableTxRegistrationHook
    ) throws -> [DurableTxId] {
        fatalError("these cases only schedule")
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
