import Foundation
import os
import Products

/// A persisted keep-alive operation opened by a product's worker.
struct ProductOperationRecord: Codable, Sendable, Equatable {
    let productId: ProductId
    let id: UInt32
    let label: String?
    let startedAt: Date
}

/// Persistence for open worker operations. A later interface will read these.
protocol ProductOperationStoring: Sendable {
    func save(_ record: ProductOperationRecord) async throws
    func delete(productId: ProductId, id: UInt32) async throws
    func all() async throws -> [ProductOperationRecord]
    func clearAll() async throws
}

/// Opens/closes worker keep-alive operations. Each open operation holds one
/// lock on the product's worker, so the worker survives while any operation is
/// open, and every operation is persisted for later inspection.
protocol ProductWorkerOperating: Sendable {
    func beginOperation(productId: ProductId, label: String?) async throws -> UInt32
    func endOperation(productId: ProductId, id: UInt32) async throws
}

final class ProductWorkerOperationService: ProductWorkerOperating, @unchecked Sendable {
    private struct State {
        var tokens: [Key: ProductWorkerToken] = [:]
    }

    private struct Key: Hashable {
        let productId: ProductId
        let id: UInt32
    }

    private let workerManager: ProductWorkerManaging
    private let store: ProductOperationStoring
    private let logger: LoggerProtocol
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    init(
        workerManager: ProductWorkerManaging,
        store: ProductOperationStoring,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.workerManager = workerManager
        self.store = store
        self.logger = logger
    }

    /// Drops operations left over from a previous process. Open operations are a
    /// process-lifetime keep-alive record: nothing keeps a worker alive across a
    /// relaunch, so stale rows left behind would pin workers forever.
    func resetForNewSession() {
        Task { [store, logger] in
            do { try await store.clearAll() } catch {
                logger.error("Failed to clear stale worker operations: \(error)")
            }
        }
    }

    func beginOperation(productId: ProductId, label: String?) async throws -> UInt32 {
        let (id, token) = state.withLock { state -> (UInt32, ProductWorkerToken) in
            // Random, host-assigned, unique among this product's open operations.
            // 0 is avoided so it never reads as an unset/default id.
            var id = UInt32.random(in: 1 ... .max)
            while state.tokens[Key(productId: productId, id: id)] != nil {
                id = UInt32.random(in: 1 ... .max)
            }
            let token = workerManager.lock(productId: productId)
            state.tokens[Key(productId: productId, id: id)] = token
            return (id, token)
        }

        do {
            try await store.save(
                ProductOperationRecord(productId: productId, id: id, label: label, startedAt: Date())
            )
        } catch {
            // Persistence failed: undo the lock so a bad row does not pin the worker.
            state.withLock { $0.tokens[Key(productId: productId, id: id)] = nil }
            token.unlock()
            throw error
        }

        return id
    }

    func endOperation(productId: ProductId, id: UInt32) async throws {
        let token = state.withLock { $0.tokens.removeValue(forKey: Key(productId: productId, id: id)) }

        // Idempotent: an unknown or already-ended id is a no-op success.
        guard let token else { return }

        // Releasing the worker is the point of ending an operation, so do it
        // unconditionally. Removing the persisted row is best-effort cleanup: a
        // failed delete must not fail `end` (host-api treats it as idempotent
        // and retryable) nor keep the worker pinned. A stale row is cleared on
        // the next launch by `resetForNewSession`.
        token.unlock()
        do {
            try await store.delete(productId: productId, id: id)
        } catch {
            logger.error("Failed to delete ended operation \(id) for \(productId): \(error)")
        }
    }
}
