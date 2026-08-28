import Foundation
import os
import Products

/// A running product worker the manager owns. Disposed when the last lock goes.
protocol ProductWorkerRunning: Sendable {
    func dispose() async
}

/// Builds and starts a headless worker runtime for a product. Injected so the
/// manager is testable without the real WKWebView/JS engine.
protocol ProductWorkerFactory: Sendable {
    func startWorker(productId: ProductId) async throws -> ProductWorkerRunning
}

/// Ref-counts a product's worker. The worker starts on the first `lock` and is
/// disposed once the last lock is released. Consumers (chats screen, the
/// product's full-page screen, open host-api operations) each hold one lock.
protocol ProductWorkerManaging: Sendable {
    /// Acquire the product's worker, starting it if this is the first lock.
    /// Balance with `ProductWorkerToken.unlock()` (or let the token deinit).
    func lock(productId: ProductId) -> ProductWorkerToken
}

/// A single lock on a product's worker. Releases exactly once, whichever comes
/// first: an explicit `unlock()` or the token being dropped.
final class ProductWorkerToken: @unchecked Sendable {
    private let released = OSAllocatedUnfairLock(initialState: false)
    private let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    func unlock() {
        let shouldRelease = released.withLock { released -> Bool in
            guard !released else { return false }
            released = true
            return true
        }

        guard shouldRelease else { return }

        onRelease()
    }

    deinit {
        unlock()
    }
}

final class ProductWorkerManager: ProductWorkerManaging, @unchecked Sendable {
    private struct Entry {
        var refCount: Int = 0
        var worker: ProductWorkerRunning?
        /// Serializes start/dispose for this product so a dispose always runs
        /// after the start it undoes, and a re-lock waits for a pending dispose.
        var lifecycle: Task<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: [ProductId: Entry]())
    private let factory: ProductWorkerFactory?
    private let logger: LoggerProtocol

    /// `factory` boots the real JS worker on the first lock. It is optional so
    /// ref-counting and operations work before the boot path is wired — with no
    /// factory, `lock`/`unlock` still track consumers but start no JS worker.
    init(factory: ProductWorkerFactory?, logger: LoggerProtocol = Logger.shared) {
        self.factory = factory
        self.logger = logger
    }

    func lock(productId: ProductId) -> ProductWorkerToken {
        state.withLock { entries in
            var entry = entries[productId] ?? Entry()
            entry.refCount += 1
            if entry.refCount == 1 {
                entry.lifecycle = chainStart(productId: productId, after: entry.lifecycle)
            }
            entries[productId] = entry
        }

        return ProductWorkerToken { [weak self] in
            self?.release(productId: productId)
        }
    }

    private func release(productId: ProductId) {
        state.withLock { entries in
            guard var entry = entries[productId] else { return }
            entry.refCount -= 1
            guard entry.refCount <= 0 else {
                entries[productId] = entry
                return
            }
            entry.refCount = 0
            entry.lifecycle = chainDispose(productId: productId, after: entry.lifecycle)
            entries[productId] = entry
        }
    }

    /// Appends a start step to the product's lifecycle chain. Runs only if the
    /// worker is still wanted once any prior step finished.
    private func chainStart(productId: ProductId, after previous: Task<Void, Never>?) -> Task<Void, Never> {
        Task { [weak self] in
            await previous?.value
            guard let self else { return }

            let wanted = state.withLock { ($0[productId]?.refCount ?? 0) > 0 }
            guard wanted else { return }

            // No boot path wired yet: ref-counting still holds, just no JS worker.
            guard let factory else { return }

            do {
                let worker = try await factory.startWorker(productId: productId)
                let keep = state.withLock { entries -> Bool in
                    guard var entry = entries[productId], entry.refCount > 0 else { return false }
                    entry.worker = worker
                    entries[productId] = entry
                    return true
                }
                if !keep {
                    await worker.dispose()
                }
            } catch {
                logger.error("Worker start failed for \(productId): \(error)")
            }
        }
    }

    /// Appends a dispose step. Runs after any in-flight start, tears the worker
    /// down, and drops the entry if nothing re-locked it meanwhile.
    private func chainDispose(productId: ProductId, after previous: Task<Void, Never>?) -> Task<Void, Never> {
        Task { [weak self] in
            await previous?.value
            guard let self else { return }

            let worker = state.withLock { entries -> ProductWorkerRunning? in
                let worker = entries[productId]?.worker
                entries[productId]?.worker = nil
                return worker
            }
            await worker?.dispose()

            state.withLock { entries in
                if (entries[productId]?.refCount ?? 0) <= 0 {
                    entries[productId] = nil
                }
            }
        }
    }
}
