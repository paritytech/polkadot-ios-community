import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

enum DeviceTransferOutcome: Int16 {
    case rejected = 0
    case accepted = 1
}

protocol DeviceTransferProcessedStoring: Sendable {
    func markProcessed(requestId: String, outcome: DeviceTransferOutcome) async throws
    func processedRequestIds(among requestIds: [String]) async throws -> Set<String>
}

/// Remembers every request the user confirmed or rejected, so a request still on the store isn't shown again.
final class DeviceTransferProcessedCoreDataStore: @unchecked Sendable {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }
}

extension DeviceTransferProcessedCoreDataStore: DeviceTransferProcessedStoring {
    func markProcessed(requestId: String, outcome: DeviceTransferOutcome) async throws {
        let identifier = requestId.lowercased()

        try await databaseService.performWrite { context in
            let row = try Self.fetchRows(with: [identifier], in: context).first
                ?? context.insertNew(CDProcessedTransfer.self)
            row.identifier = identifier
            row.outcome = outcome.rawValue
        }
    }

    func processedRequestIds(among requestIds: [String]) async throws -> Set<String> {
        let identifiers = requestIds.map { $0.lowercased() }

        return try await databaseService.performRead { context in
            try Set(Self.fetchRows(with: identifiers, in: context).compactMap(\.identifier))
        }
    }
}

private extension DeviceTransferProcessedCoreDataStore {
    static func fetchRows(
        with identifiers: [String],
        in context: NSManagedObjectContext
    ) throws -> [CDProcessedTransfer] {
        let request = NSFetchRequest<CDProcessedTransfer>(entityName: "CDProcessedTransfer")
        request.predicate = NSPredicate(format: "%K IN %@", #keyPath(CDProcessedTransfer.identifier), identifiers)
        return try context.fetch(request)
    }
}
