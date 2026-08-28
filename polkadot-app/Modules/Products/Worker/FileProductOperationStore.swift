import Foundation
import Products

/// JSON-file persistence for open worker operations in the shared container.
///
/// A flat file rather than a CoreData entity on purpose: open operations are a
/// small, process-lifetime keep-alive record and there is no listing UI for them
/// yet. Swap this for a CoreData-backed store behind `ProductOperationStoring`
/// once that UI lands and the store migration can be verified on device.
actor FileProductOperationStore: ProductOperationStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        directory: URL = SharedContainerGroup.containerURL.appendingPathComponent("ProductWorker"),
        fileName: String = "operations.json",
        fileManager: FileManager = .default
    ) {
        fileURL = directory.appendingPathComponent(fileName)
        self.fileManager = fileManager
    }

    func save(_ record: ProductOperationRecord) async throws {
        var records = try load()
        records.removeAll { $0.productId == record.productId && $0.id == record.id }
        records.append(record)
        try persist(records)
    }

    func delete(productId: ProductId, id: UInt32) async throws {
        var records = try load()
        let before = records.count
        records.removeAll { $0.productId == productId && $0.id == id }
        guard records.count != before else { return }
        try persist(records)
    }

    func all() async throws -> [ProductOperationRecord] {
        try load()
    }

    func clearAll() async throws {
        try persist([])
    }

    private func load() throws -> [ProductOperationRecord] {
        guard let data = fileManager.contents(atPath: fileURL.path), !data.isEmpty else { return [] }
        return try JSONDecoder().decode([ProductOperationRecord].self, from: data)
    }

    private func persist(_ records: [ProductOperationRecord]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
