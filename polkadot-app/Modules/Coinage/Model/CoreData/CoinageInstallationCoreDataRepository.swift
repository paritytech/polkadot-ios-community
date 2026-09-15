import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// CoreData-backed ``CoinageInstallationRepositoryProtocol``. Every operation runs as one block on
/// the store's single context, so `getOrCreateCurrent` reads and inserts atomically: concurrent first
/// callers on a fresh install all end up with the same id.
final class CoinageInstallationCoreDataRepository: CoinageInstallationRepositoryProtocol, @unchecked Sendable {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }

    func getOrCreateCurrent() async throws -> CoinageInstallationId {
        try await databaseService.perform { context in
            if let current: CDCoinageInstallation = try context.first(for: Self.currentPredicate) {
                return try CoinageInstallationId(hex: Self.identifier(of: current))
            }

            let created = try CoinageInstallationId.random()
            let row = try context.insertNew(CDCoinageInstallation.self)
            row.identifier = created.hex
            row.isCurrent = true
            row.coinScanNextIndex = 0
            row.voucherScanNextIndex = 0
            row.initialScanCompleted = true
            try context.save()
            return created
        }
    }

    func addPrevious(_ installations: [CoinageInstallationId]) async throws {
        let current = try await getOrCreateCurrent()
        let previous = Set(installations).subtracting([current])
        guard !previous.isEmpty else { return }

        try await databaseService.perform { context in
            for installation in previous {
                let existing: CDCoinageInstallation? = try context.first(for: Self.predicate(for: installation))
                guard existing == nil else { continue }

                let row = try context.insertNew(CDCoinageInstallation.self)
                row.identifier = installation.hex
                row.isCurrent = false
                row.coinScanNextIndex = 0
                row.voucherScanNextIndex = 0
                row.initialScanCompleted = false
            }
            try context.save()
        }
    }

    func getPrevious() async throws -> [PreviousInstallation] {
        try await databaseService.perform { context in
            let request = NSFetchRequest<CDCoinageInstallation>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "%K == NO", #keyPath(CDCoinageInstallation.isCurrent))
            let byIdentifier = NSSortDescriptor(key: #keyPath(CDCoinageInstallation.identifier), ascending: true)
            request.sortDescriptors = [byIdentifier]

            return try context.fetch(request).map { row in
                try PreviousInstallation(
                    id: CoinageInstallationId(hex: Self.identifier(of: row)),
                    coinScanNextIndex: UInt32(clamping: row.coinScanNextIndex),
                    voucherScanNextIndex: UInt32(clamping: row.voucherScanNextIndex),
                    initialScanCompleted: row.initialScanCompleted
                )
            }
        }
    }

    func updateCoinScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws {
        try await update(installation) { $0.coinScanNextIndex = Int64(nextIndex) }
    }

    func updateVoucherScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws {
        try await update(installation) { $0.voucherScanNextIndex = Int64(nextIndex) }
    }

    func markInitialScanCompleted(_ installation: CoinageInstallationId) async throws {
        try await update(installation) { $0.initialScanCompleted = true }
    }
}

private extension CoinageInstallationCoreDataRepository {
    static let entityName = "CDCoinageInstallation"

    static let currentPredicate = NSPredicate(format: "%K == YES", #keyPath(CDCoinageInstallation.isCurrent))

    static func predicate(for installation: CoinageInstallationId) -> NSPredicate {
        NSPredicate(format: "%K == %@", #keyPath(CDCoinageInstallation.identifier), installation.hex)
    }

    static func identifier(of row: CDCoinageInstallation) throws -> String {
        guard let identifier = row.identifier else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCoinageInstallation.identifier))
        }
        return identifier
    }

    func update(
        _ installation: CoinageInstallationId,
        _ change: @escaping (CDCoinageInstallation) -> Void
    ) async throws {
        try await databaseService.perform { context in
            guard let row: CDCoinageInstallation = try context.first(for: Self.predicate(for: installation)) else {
                throw CoinageInstallationRepositoryError.unknownInstallation(installation)
            }
            change(row)
            try context.save()
        }
    }
}

enum CoinageInstallationRepositoryError: Error {
    case unknownInstallation(CoinageInstallationId)
}
