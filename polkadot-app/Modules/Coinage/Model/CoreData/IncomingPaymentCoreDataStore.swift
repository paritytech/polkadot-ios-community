import AsyncExtensions
import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// CoreData-backed ``IncomingPaymentStoring``. Records are keyed by their `groupId`
/// (`"top up:productId:paymentId"`) as `identifier`, hold no secrets, and are settled once with a
/// terminal verdict; "active" means `outcomeTag == nil`.
final class IncomingPaymentCoreDataStore: IncomingPaymentStoring, @unchecked Sendable {
    private let storageFacade: StorageFacadeProtocol
    private let repository: AnyDataProviderRepository<IncomingPayment>
    private let outcomeRepository: AnyDataProviderRepository<IncomingPaymentOutcomeUpdate>
    private let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.storageFacade = storageFacade
        self.logger = logger

        let fullRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(IncomingPaymentMapper())
        )
        repository = AnyDataProviderRepository(fullRepository)

        let outcomeRepo = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(IncomingPaymentOutcomeMapper())
        )
        outcomeRepository = AnyDataProviderRepository(outcomeRepo)
    }

    func save(_ payment: IncomingPayment) async throws {
        try await repository.saveOperation({ [payment] }, { [] }).asyncExecute()
    }

    func fetch(groupId: CoinageTxGroupId) async throws -> IncomingPayment? {
        try await repository.fetchOperation(by: { groupId }, options: .init()).asyncExecute()
    }

    func fetchActivePayments() async throws -> [IncomingPayment] {
        try await activeRepository()
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
    }

    func settle(groupId: CoinageTxGroupId, outcome: IncomingPaymentTerminalOutcome) async throws {
        let update = IncomingPaymentOutcomeUpdate(groupId: groupId, outcome: outcome)
        try await outcomeRepository.saveOperation({ [update] }, { [] }).asyncExecute()
    }

    func observePayment(groupId: CoinageTxGroupId) -> AnyAsyncSequence<IncomingPayment?> {
        storageFacade.subscribeSingle(
            mapper: AnyCoreDataMapper(IncomingPaymentMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDIncomingPayment.identifier), groupId)
        )
    }

    func observeActivePayments() -> AnyAsyncSequence<[IncomingPayment]> {
        storageFacade.subscribeSnapshot(
            mapper: AnyCoreDataMapper(IncomingPaymentMapper()),
            filter: Self.activeFilter
        )
    }
}

// MARK: - Private

private extension IncomingPaymentCoreDataStore {
    static var activeFilter: NSPredicate {
        NSPredicate(format: "%K == nil", #keyPath(CDIncomingPayment.outcomeTag))
    }

    func activeRepository() -> AnyDataProviderRepository<IncomingPayment> {
        let repository = storageFacade.createRepository(
            filter: Self.activeFilter,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(IncomingPaymentMapper())
        )
        return AnyDataProviderRepository(repository)
    }
}
