import Coinage
import CoreData
import Foundation
import Testing
@testable import polkadot_app

struct VoucherInclusionMigrationTests {
    @Test
    func migrationPreservesLegacyVouchersAndConfirmedTimeSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vouchers.sqlite")
        let firstObservation = Date(timeIntervalSince1970: 1_000)

        try withStore(version: .version45, at: url) { context in
            let voucher = NSEntityDescription.insertNewObject(forEntityName: "CDVoucher", into: context)
            voucher.setValuesForKeys([
                "identifier": "7",
                "derivationIndex": Int64(7),
                "exponent": Int16(3),
                "allocatedAt": firstObservation,
                "readyAt": firstObservation,
                "publicKey": "07",
                "onChainState": Int16(2),
                "recyclerIndex": Int64(2),
                "recyclerMembers": Int64(32)
            ])
            try context.save()
        }

        try withStore(version: .version46, at: url) { context in
            let entity = try #require(context.fetch(CDVoucher.fetchRequest()).first)
            let mapper = VoucherMapper()
            let voucher = try mapper.transform(entity: entity)
            #expect(voucher.recycler == .init(index: 2, membersCount: 32))

            let update = VoucherLocationUpdate(
                derivationIndex: 7,
                remoteState: .inRecycler(.init(index: 2, membersCount: 32, enteredAt: firstObservation))
            )
            try VoucherLocationMapper().populate(entity: entity, from: update, using: context)
            try context.save()
        }

        try withStore(version: .version46, at: url) { context in
            let entity = try #require(context.fetch(CDVoucher.fetchRequest()).first)
            let voucher = try VoucherMapper().transform(entity: entity)
            #expect(voucher.recycler == .init(index: 2, membersCount: 32, enteredAt: firstObservation))
        }
    }
}

private extension VoucherInclusionMigrationTests {
    func withStore(
        version: UserStorageVersion,
        at url: URL,
        body: (NSManagedObjectContext) throws -> Void
    ) throws {
        let modelURL = try #require(Bundle.main.url(
            forResource: version.rawValue,
            withExtension: "mom",
            subdirectory: UserStorageParams.modelDirectory
        ))
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
        )
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait { try body(context) }
    }
}
