import Coinage
import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// The highest coin and voucher item stored under an installation, for the allocators' `max + 1`.
final class CoinageKeyIndexQueries: CoinageKeyIndexQuerying, @unchecked Sendable {
    private let databaseService: CoreDataServiceProtocol

    init(storageFacade: StorageFacadeProtocol) {
        databaseService = storageFacade.databaseService
    }

    func maxCoinItem(in installation: CoinageInstallationId) async throws -> UInt32? {
        try await maxItem(
            entityName: "CDCoin",
            installationKey: #keyPath(CDCoin.installationId),
            itemKey: #keyPath(CDCoin.derivationIndex),
            installation: installation
        )
    }

    func maxVoucherItem(in installation: CoinageInstallationId) async throws -> UInt32? {
        try await maxItem(
            entityName: "CDVoucher",
            installationKey: #keyPath(CDVoucher.installationId),
            itemKey: #keyPath(CDVoucher.derivationIndex),
            installation: installation
        )
    }
}

private extension CoinageKeyIndexQueries {
    func maxItem(
        entityName: String,
        installationKey: String,
        itemKey: String,
        installation: CoinageInstallationId
    ) async throws -> UInt32? {
        try await databaseService.perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "%K == %@", installationKey, installation.hex)
            request.sortDescriptors = [NSSortDescriptor(key: itemKey, ascending: false)]
            request.fetchLimit = 1

            guard let row = try context.fetch(request).first,
                  let item = row.value(forKey: itemKey) as? Int64
            else { return nil }
            return UInt32(clamping: item)
        }
    }
}
