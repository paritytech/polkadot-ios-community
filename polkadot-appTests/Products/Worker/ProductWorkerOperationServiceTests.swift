import Testing
import Foundation
import os
import Products
@testable import polkadot_app

private final class FakeWorkerManager: ProductWorkerManaging, @unchecked Sendable {
    private let active = OSAllocatedUnfairLock(initialState: 0)

    func lock(productId _: ProductId) -> ProductWorkerToken {
        active.withLock { $0 += 1 }
        return ProductWorkerToken { [active] in active.withLock { $0 -= 1 } }
    }

    func acquire(productId: ProductId) async -> ProductWorkerLease {
        ProductWorkerLease(token: lock(productId: productId), worker: nil)
    }

    var activeCount: Int { active.withLock { $0 } }
}

private struct StoreError: Error {}

private final class FakeOperationStore: ProductOperationStoring, @unchecked Sendable {
    private let records = OSAllocatedUnfairLock(initialState: [ProductOperationRecord]())
    private let failSave: Bool
    private let failDelete: Bool

    init(failSave: Bool = false, failDelete: Bool = false) {
        self.failSave = failSave
        self.failDelete = failDelete
    }

    func save(_ record: ProductOperationRecord) async throws {
        if failSave {
            throw StoreError()
        }
        records.withLock { $0.append(record) }
    }

    func delete(productId: ProductId, id: UInt32) async throws {
        if failDelete {
            throw StoreError()
        }
        records.withLock { $0.removeAll { $0.productId == productId && $0.id == id } }
    }

    func all() async throws -> [ProductOperationRecord] { records.withLock { $0 } }
    func clearAll() async throws { records.withLock { $0 = [] } }

    var count: Int { records.withLock { $0.count } }
    var isEmpty: Bool { records.withLock { $0.isEmpty } }
}

@Suite("ProductWorkerOperationService")
struct ProductWorkerOperationServiceTests {
    @Test("begin assigns distinct non-zero ids, locks the worker, and persists")
    func beginLocksAndPersists() async throws {
        let manager = FakeWorkerManager()
        let store = FakeOperationStore()
        let service = ProductWorkerOperationService(workerManager: manager, store: store)

        let first = try await service.beginOperation(productId: "getcash", label: "sync")
        let second = try await service.beginOperation(productId: "getcash", label: nil)

        #expect(first != 0)
        #expect(second != 0)
        #expect(first != second)
        #expect(manager.activeCount == 2)
        #expect(store.count == 2)
    }

    @Test("end unlocks the worker, removes the record, and is idempotent")
    func endUnlocksAndIsIdempotent() async throws {
        let manager = FakeWorkerManager()
        let store = FakeOperationStore()
        let service = ProductWorkerOperationService(workerManager: manager, store: store)

        let id = try await service.beginOperation(productId: "getcash", label: nil)
        #expect(manager.activeCount == 1)

        try await service.endOperation(productId: "getcash", id: id)
        #expect(manager.activeCount == 0)
        #expect(store.isEmpty)

        // Ending again, or ending an unknown id, must not go negative or throw.
        try await service.endOperation(productId: "getcash", id: id)
        try await service.endOperation(productId: "getcash", id: 999)
        #expect(manager.activeCount == 0)
    }

    @Test("end still releases the worker and succeeds when deleting the record fails")
    func endReleasesWorkerEvenIfDeleteFails() async throws {
        let manager = FakeWorkerManager()
        let store = FakeOperationStore(failDelete: true)
        let service = ProductWorkerOperationService(workerManager: manager, store: store)

        let id = try await service.beginOperation(productId: "getcash", label: nil)
        #expect(manager.activeCount == 1)

        // A failing delete must not throw and must not pin the worker.
        try await service.endOperation(productId: "getcash", id: id)
        #expect(manager.activeCount == 0)
    }

    @Test("a persistence failure on begin releases the lock")
    func beginUndoesLockWhenPersistFails() async {
        let manager = FakeWorkerManager()
        let store = FakeOperationStore(failSave: true)
        let service = ProductWorkerOperationService(workerManager: manager, store: store)

        await #expect(throws: (any Error).self) {
            _ = try await service.beginOperation(productId: "getcash", label: nil)
        }
        #expect(manager.activeCount == 0)
        #expect(store.isEmpty)
    }
}
